package config

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// Config holds the user's configuration.
type Config struct {
	AddOnsPath string `json:"addons_path"`
}

var configDir string
var configFile string

func init() {
	home, err := os.UserHomeDir()
	if err != nil {
		home = "."
	}
	configDir = filepath.Join(home, ".adhdbis")
	configFile = filepath.Join(configDir, "config.json")
}

// Load reads the config from disk. Returns nil config if not found.
func Load() (*Config, error) {
	data, err := os.ReadFile(configFile)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("reading config: %w", err)
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parsing config: %w", err)
	}
	if cfg.AddOnsPath == "" {
		return nil, nil
	}
	return &cfg, nil
}

// Save writes the config to disk.
func Save(cfg *Config) error {
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return fmt.Errorf("creating config dir: %w", err)
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("marshaling config: %w", err)
	}
	if err := os.WriteFile(configFile, data, 0644); err != nil {
		return fmt.Errorf("writing config: %w", err)
	}
	return nil
}

// DetectAddOnsPath tries to find WoW AddOns folder automatically.
// Returns empty string if not found.
func DetectAddOnsPath() string {
	home, _ := os.UserHomeDir()

	var candidates []string

	switch runtime.GOOS {
	case "darwin": // macOS
		candidates = []string{
			"/Applications/World of Warcraft/_midnight_/Interface/AddOns",
			"/Applications/World of Warcraft/_retail_/Interface/AddOns",
			filepath.Join(home, "Applications/World of Warcraft/_midnight_/Interface/AddOns"),
		}
	case "windows":
		candidates = []string{
			`C:\Program Files (x86)\World of Warcraft\_midnight_\Interface\AddOns`,
			`C:\Program Files\World of Warcraft\_midnight_\Interface\AddOns`,
			`D:\World of Warcraft\_midnight_\Interface\AddOns`,
			`D:\Games\World of Warcraft\_midnight_\Interface\AddOns`,
			`C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns`,
		}
	case "linux":
		candidates = []string{
			filepath.Join(home, "Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_midnight_/Interface/AddOns"),
			filepath.Join(home, ".wine/drive_c/Program Files (x86)/World of Warcraft/_midnight_/Interface/AddOns"),
			filepath.Join(home, ".local/share/lutris/runners/wine/wow/drive_c/Program Files (x86)/World of Warcraft/_midnight_/Interface/AddOns"),
		}
	}

	// First pass: check if ADHDBiS folder already exists (addon installed)
	for _, path := range candidates {
		addonDir := filepath.Join(path, "ADHDBiS")
		if info, err := os.Stat(addonDir); err == nil && info.IsDir() {
			return path
		}
	}

	// Second pass: check if AddOns folder exists (WoW installed, addon not yet)
	for _, path := range candidates {
		if info, err := os.Stat(path); err == nil && info.IsDir() {
			return path
		}
	}

	return ""
}

// PromptForPath asks the user for their WoW AddOns directory.
func PromptForPath(reader *bufio.Reader) (string, error) {
	fmt.Println()
	fmt.Println("No AddOns path configured.")
	fmt.Println("Please enter the path to your WoW AddOns folder.")
	fmt.Println("  Example (macOS): /Applications/World of Warcraft/_midnight_/Interface/AddOns")
	fmt.Println("  Example (Windows): C:\\Program Files (x86)\\World of Warcraft\\_midnight_\\Interface\\AddOns")
	fmt.Print("\nAddOns path: ")

	path, err := reader.ReadString('\n')
	if err != nil {
		return "", fmt.Errorf("reading input: %w", err)
	}
	path = strings.TrimSpace(path)

	// Validate the path exists
	info, err := os.Stat(path)
	if err != nil {
		return "", fmt.Errorf("path does not exist: %s", path)
	}
	if !info.IsDir() {
		return "", fmt.Errorf("path is not a directory: %s", path)
	}

	return path, nil
}

// EnsureConfig loads config or auto-detects/prompts user to create one.
func EnsureConfig(reader *bufio.Reader) (*Config, error) {
	cfg, err := Load()
	if err != nil {
		fmt.Printf("Warning: could not load config: %v\n", err)
	}

	if cfg != nil {
		// Verify saved path still exists
		if info, err := os.Stat(cfg.AddOnsPath); err == nil && info.IsDir() {
			fmt.Printf("AddOns path: %s\n", cfg.AddOnsPath)
			return cfg, nil
		}
		fmt.Printf("Warning: saved path no longer exists: %s\n", cfg.AddOnsPath)
	}

	// Try auto-detection
	detected := DetectAddOnsPath()
	if detected != "" {
		fmt.Printf("\nAuto-detected WoW AddOns folder:\n  %s\n", detected)
		fmt.Print("Use this path? (Y/n): ")
		answer, _ := reader.ReadString('\n')
		answer = strings.TrimSpace(strings.ToLower(answer))
		if answer == "" || answer == "y" || answer == "yes" {
			cfg = &Config{AddOnsPath: detected}
			if err := Save(cfg); err != nil {
				fmt.Printf("Warning: could not save config: %v\n", err)
			} else {
				fmt.Println("Config saved!")
			}
			return cfg, nil
		}
	}

	// Manual input fallback
	path, err := PromptForPath(reader)
	if err != nil {
		return nil, err
	}

	cfg = &Config{AddOnsPath: path}
	if err := Save(cfg); err != nil {
		fmt.Printf("Warning: could not save config: %v\n", err)
	} else {
		fmt.Println("Config saved!")
	}

	return cfg, nil
}

// DetectAddOnsPathForGUI is like DetectAddOnsPath but returns the path for GUI use.
func DetectAddOnsPathForGUI() string {
	// First try saved config
	cfg, _ := Load()
	if cfg != nil {
		if info, err := os.Stat(cfg.AddOnsPath); err == nil && info.IsDir() {
			return cfg.AddOnsPath
		}
	}
	// Then auto-detect
	return DetectAddOnsPath()
}
