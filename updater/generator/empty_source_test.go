package generator

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"adhdbis-updater/scraper"
)

// A source that fetched nothing (Wowhead answering 403 to a region, a site outage)
// must not be written: the addon would offer it in the source dropdown with no items.
func TestGenerateLuaSkipsEmptySource(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "ADHDBiS"), 0755); err != nil {
		t.Fatal(err)
	}
	all := map[string]map[string]map[string]*scraper.SpecData{
		"Death Knight": {
			"Frost": {
				"Icy Veins": {Name: "Frost", OverallGear: []scraper.GearItem{{Slot: "Head", ItemID: 281239, Name: "Corroded Hulk's Skullcap"}}},
				"Wowhead":   {Name: "Frost", ScrapedAt: "2026-11-08T21:00:00Z"},
			},
		},
	}
	if err := GenerateLua(all, dir, "All"); err != nil {
		t.Fatal(err)
	}
	out, err := os.ReadFile(filepath.Join(dir, "ADHDBiS", "ADHDBiS_Data.lua"))
	if err != nil {
		t.Fatal(err)
	}
	s := string(out)
	if !strings.Contains(s, `["Icy Veins"]`) {
		t.Fatal("Icy Veins source missing")
	}
	if strings.Contains(s, `["Wowhead"]`) {
		t.Fatal("empty Wowhead source was written")
	}
}
