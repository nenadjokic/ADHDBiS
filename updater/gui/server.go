package gui

import (
	"embed"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os/exec"
	"runtime"
	"strings"
	"sync"

	"adhdbis-updater/config"
	"adhdbis-updater/generator"
	"adhdbis-updater/scraper"
)

//go:embed static/*
var staticFiles embed.FS

type progressWriter struct {
	mu       sync.Mutex
	messages []string
	ch       chan string
}

func newProgressWriter() *progressWriter {
	return &progressWriter{ch: make(chan string, 100)}
}

func (pw *progressWriter) Write(p []byte) (n int, err error) {
	msg := string(p)
	pw.mu.Lock()
	pw.messages = append(pw.messages, msg)
	pw.mu.Unlock()
	select {
	case pw.ch <- msg:
	default:
	}
	return len(p), nil
}

var (
	currentJob *progressWriter
	jobRunning bool
	jobMu      sync.Mutex
)

func StartServer(cfg *config.Config) {
	mux := http.NewServeMux()

	// Serve static files
	mux.Handle("/static/", http.FileServer(http.FS(staticFiles)))

	// Serve index.html at root
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		data, err := staticFiles.ReadFile("static/index.html")
		if err != nil {
			http.Error(w, "Not found", 404)
			return
		}
		w.Header().Set("Content-Type", "text/html")
		html := strings.Replace(string(data), "{{COMPANION_VERSION}}", generator.CompanionVersion, 1)
		w.Write([]byte(html))
	})

	// API: Get classes
	mux.HandleFunc("/api/classes", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(scraper.AllClasses)
	})

	// API: Get config
	mux.HandleFunc("/api/config", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Method == "POST" {
			// Update path
			var body struct {
				AddOnsPath string `json:"addonsPath"`
			}
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				http.Error(w, "Invalid JSON", 400)
				return
			}
			body.AddOnsPath = strings.TrimSpace(body.AddOnsPath)
			if body.AddOnsPath == "" {
				http.Error(w, "Path cannot be empty", 400)
				return
			}
			cfg.AddOnsPath = body.AddOnsPath
			config.Save(cfg)
			json.NewEncoder(w).Encode(map[string]string{
				"addonsPath": cfg.AddOnsPath,
				"status":     "saved",
			})
			return
		}
		// GET
		detected := config.DetectAddOnsPath()
		json.NewEncoder(w).Encode(map[string]string{
			"addonsPath": cfg.AddOnsPath,
			"detected":   detected,
		})
	})

	// API: Get status
	mux.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		jobMu.Lock()
		running := jobRunning
		jobMu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]bool{"running": running})
	})

	// API: Start scrape
	mux.HandleFunc("/api/scrape", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			http.Error(w, "POST only", 405)
			return
		}

		jobMu.Lock()
		if jobRunning {
			jobMu.Unlock()
			http.Error(w, "Scrape already in progress", 409)
			return
		}
		jobRunning = true
		jobMu.Unlock()

		var req struct {
			Source  string `json:"source"`
			Classes []int  `json:"classes"` // indices into AllClasses, empty = all
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			jobMu.Lock()
			jobRunning = false
			jobMu.Unlock()
			http.Error(w, err.Error(), 400)
			return
		}

		// Build scrape request
		var classes []scraper.ClassInfo
		classSpecs := map[string][]scraper.ClassSpec{}

		if len(req.Classes) == 0 {
			classes = scraper.AllClasses
			for _, c := range classes {
				classSpecs[c.Name] = c.Specs
			}
		} else {
			for _, idx := range req.Classes {
				if idx >= 0 && idx < len(scraper.AllClasses) {
					c := scraper.AllClasses[idx]
					classes = append(classes, c)
					classSpecs[c.Name] = c.Specs
				}
			}
		}

		source := req.Source
		if source == "" {
			source = "Icy Veins"
		}

		var sources []string
		if source == "Both" {
			sources = []string{"Icy Veins", "Wowhead"}
		} else {
			sources = []string{source}
		}

		pw := newProgressWriter()
		jobMu.Lock()
		currentJob = pw
		jobMu.Unlock()

		go func() {
			defer func() {
				jobMu.Lock()
				jobRunning = false
				jobMu.Unlock()
			}()

			scrapeReq := scraper.ScrapeRequest{
				Classes:    classes,
				ClassSpecs: classSpecs,
				Sources:    sources,
			}

			result := scraper.RunScrape(scrapeReq, pw)

			fmt.Fprintf(pw, "=== Generating Lua Data File ===\n")
			if err := generator.GenerateLua(result.AllData, cfg.AddOnsPath, source); err != nil {
				fmt.Fprintf(pw, "Error: %v\n", err)
			}

			fmt.Fprintf(pw, "\nUpdate complete! %d classes, %d data points\n", len(classes), result.TotalItems)
			fmt.Fprintf(pw, "Reload your UI in-game with /reload\n")

			// Signal completion
			pw.ch <- "[[DONE]]"
		}()

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "started"})
	})

	// API: Stream progress via SSE
	mux.HandleFunc("/api/progress", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")

		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "Streaming not supported", 500)
			return
		}

		jobMu.Lock()
		pw := currentJob
		jobMu.Unlock()

		if pw == nil {
			fmt.Fprintf(w, "data: [[DONE]]\n\n")
			flusher.Flush()
			return
		}

		// Send existing messages first
		pw.mu.Lock()
		for _, msg := range pw.messages {
			fmt.Fprintf(w, "data: %s\n\n", strings.ReplaceAll(strings.TrimRight(msg, "\n"), "\n", "\\n"))
			flusher.Flush()
		}
		pw.mu.Unlock()

		// Stream new messages
		for msg := range pw.ch {
			fmt.Fprintf(w, "data: %s\n\n", strings.ReplaceAll(strings.TrimRight(msg, "\n"), "\n", "\\n"))
			flusher.Flush()
			if msg == "[[DONE]]" {
				return
			}
		}
	})

	// Find available port
	port := 8713
	listener, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		// Try random port
		listener, err = net.Listen("tcp", ":0")
		if err != nil {
			fmt.Printf("Error starting server: %v\n", err)
			return
		}
		port = listener.Addr().(*net.TCPAddr).Port
	}

	url := fmt.Sprintf("http://localhost:%d", port)
	fmt.Printf("ADHDBiS Updater GUI running at %s\n", url)
	fmt.Println("Press Ctrl+C to stop")

	// Open browser
	openBrowser(url)

	http.Serve(listener, mux)
}

func openBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "linux":
		cmd = exec.Command("xdg-open", url)
	case "windows":
		cmd = exec.Command("cmd", "/c", "start", url)
	}
	if cmd != nil {
		cmd.Start()
	}
}
