package config

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
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

// PromptForPath asks the user for their WoW AddOns directory.
func PromptForPath(reader *bufio.Reader) (string, error) {
	fmt.Println()
	fmt.Println("No AddOns path configured.")
	fmt.Println("Please enter the path to your WoW AddOns folder.")
	fmt.Println("  Example (macOS): /Applications/World of Warcraft/_retail_/Interface/AddOns")
	fmt.Println("  Example (Windows): C:\\Program Files (x86)\\World of Warcraft\\_retail_\\Interface\\AddOns")
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

// EnsureConfig loads config or prompts user to create one.
func EnsureConfig(reader *bufio.Reader) (*Config, error) {
	cfg, err := Load()
	if err != nil {
		fmt.Printf("Warning: could not load config: %v\n", err)
	}

	if cfg != nil {
		fmt.Printf("AddOns path: %s\n", cfg.AddOnsPath)
		return cfg, nil
	}

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
