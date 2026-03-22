package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"

	"adhdbis-updater/config"
	"adhdbis-updater/generator"
	"adhdbis-updater/gui"
	"adhdbis-updater/scraper"
)

const banner = `
╔═══════════════════════════════════════╗
║       ADHDBiS Updater v1.3           ║
║    BiS Data for any WoW Class        ║
╚═══════════════════════════════════════╝
`

func main() {
	// CLI mode only when explicitly requested with --cli flag
	cliMode := false
	for _, arg := range os.Args[1:] {
		if arg == "--cli" || arg == "cli" {
			cliMode = true
			break
		}
	}

	if !cliMode {
		// Default: GUI mode
		reader := bufio.NewReader(os.Stdin)
		cfg, err := config.EnsureConfig(reader)
		if err != nil {
			fmt.Printf("Error: %v\n", err)
			os.Exit(1)
		}
		gui.StartServer(cfg)
		return
	}

	fmt.Print(banner)
	reader := bufio.NewReader(os.Stdin)

	// Load or create config
	cfg, err := config.EnsureConfig(reader)
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}

	// Source selection
	fmt.Println("\nData source:")
	fmt.Println("  [1] Icy Veins (recommended)")
	fmt.Println("  [2] Wowhead")
	fmt.Println("  [3] Both (takes longer, enables in-game source switching)")
	fmt.Print("Choose [1]: ")
	sourceInput, _ := reader.ReadString('\n')
	sourceChoice := strings.TrimSpace(sourceInput)

	var sources []string
	var sourceName string
	switch sourceChoice {
	case "2":
		sources = []string{"Wowhead"}
		sourceName = "Wowhead"
	case "3":
		sources = []string{"Icy Veins", "Wowhead"}
		sourceName = "Both"
	default:
		sources = []string{"Icy Veins"}
		sourceName = "Icy Veins"
	}

	// Class selection
	fmt.Println("\nSelect class:")
	fmt.Println("  [ 0] All classes")
	for i, class := range scraper.AllClasses {
		fmt.Printf("  [%2d] %s\n", i+1, class.Name)
	}
	fmt.Print("Choose: ")
	classInput, _ := reader.ReadString('\n')
	classChoice := strings.TrimSpace(classInput)

	var classesToScrape []scraper.ClassInfo
	allClassesMode := false

	if classChoice == "0" {
		allClassesMode = true
		classesToScrape = scraper.AllClasses
	} else {
		classIdx, err := strconv.Atoi(classChoice)
		if err != nil || classIdx < 1 || classIdx > len(scraper.AllClasses) {
			fmt.Println("Invalid selection.")
			os.Exit(1)
		}
		classesToScrape = []scraper.ClassInfo{scraper.AllClasses[classIdx-1]}
	}

	// Spec selection (only for single class)
	classSpecs := map[string][]scraper.ClassSpec{} // className -> specs to scrape

	if allClassesMode {
		for _, class := range classesToScrape {
			classSpecs[class.Name] = class.Specs
		}
	} else {
		selectedClass := classesToScrape[0]
		fmt.Printf("\n%s specs:\n", selectedClass.Name)
		fmt.Println("  [0] All specs")
		for i, spec := range selectedClass.Specs {
			fmt.Printf("  [%d] %s (%s)\n", i+1, spec.Name, spec.Role)
		}
		fmt.Print("Choose [0]: ")
		specInput, _ := reader.ReadString('\n')
		specChoice := strings.TrimSpace(specInput)

		if specChoice == "" || specChoice == "0" {
			classSpecs[selectedClass.Name] = selectedClass.Specs
		} else {
			specIdx, err := strconv.Atoi(specChoice)
			if err != nil || specIdx < 1 || specIdx > len(selectedClass.Specs) {
				fmt.Println("Invalid selection.")
				os.Exit(1)
			}
			classSpecs[selectedClass.Name] = []scraper.ClassSpec{selectedClass.Specs[specIdx-1]}
		}
	}

	// Confirm
	fmt.Printf("\nSource: %s\n", sourceName)
	if allClassesMode {
		fmt.Println("Classes: All (13 classes)")
	} else {
		cls := classesToScrape[0]
		specs := classSpecs[cls.Name]
		specNames := make([]string, len(specs))
		for i, s := range specs {
			specNames[i] = s.Name
		}
		fmt.Printf("Class:  %s\n", cls.Name)
		fmt.Printf("Specs:  %s\n", strings.Join(specNames, ", "))
	}
	fmt.Print("\nPress Enter to start update...")
	reader.ReadString('\n')
	fmt.Println()

	// Scrape using RunScrape
	result := scraper.RunScrape(scraper.ScrapeRequest{
		Classes:    classesToScrape,
		ClassSpecs: classSpecs,
		Sources:    sources,
	}, os.Stdout)

	// Generate
	fmt.Println("=== Generating Lua Data File ===")
	if err := generator.GenerateLua(result.AllData, cfg.AddOnsPath, sourceName); err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}

	fmt.Println()
	fmt.Println("╔═══════════════════════════════════════╗")
	fmt.Println("║            Update Complete!            ║")
	fmt.Println("╚═══════════════════════════════════════╝")
	fmt.Printf("  Source: %s\n", sourceName)
	fmt.Printf("  Classes: %d\n", len(classesToScrape))
	totalSpecs := 0
	for _, specs := range classSpecs {
		totalSpecs += len(specs)
	}
	fmt.Printf("  Specs:   %d\n", totalSpecs)
	fmt.Printf("  Total data points: %d\n", result.TotalItems)
	fmt.Println("  Reload your UI in-game with /reload")
	fmt.Println()
}
