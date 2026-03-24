package scraper

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

var LogWriter io.Writer = os.Stdout

func logf(format string, a ...any) {
	fmt.Fprintf(LogWriter, format, a...)
}

const (
	userAgent    = "ADHDBiS-Updater/1.0 (WoW Addon Helper)"
	requestDelay = 1500 * time.Millisecond
)

// ClassSpec defines a specialization with its URL slug and role.
type ClassSpec struct {
	Name    string // Display name (e.g., "Demonology")
	Slug    string // URL slug (e.g., "demonology")
	Role    string // "dps", "healer", "tank"
}

// ClassInfo defines a class and its specializations.
type ClassInfo struct {
	Name      string      // Display name (e.g., "Warlock")
	Slug      string      // URL slug (e.g., "warlock")
	Specs     []ClassSpec
}

// AllClasses defines every WoW class and spec with Icy Veins URL info.
var AllClasses = []ClassInfo{
	{Name: "Death Knight", Slug: "death-knight", Specs: []ClassSpec{
		{Name: "Blood", Slug: "blood", Role: "tank"},
		{Name: "Frost", Slug: "frost", Role: "dps"},
		{Name: "Unholy", Slug: "unholy", Role: "dps"},
	}},
	{Name: "Demon Hunter", Slug: "demon-hunter", Specs: []ClassSpec{
		{Name: "Devourer", Slug: "devourer", Role: "dps"},
		{Name: "Havoc", Slug: "havoc", Role: "dps"},
		{Name: "Vengeance", Slug: "vengeance", Role: "tank"},
	}},
	{Name: "Druid", Slug: "druid", Specs: []ClassSpec{
		{Name: "Balance", Slug: "balance", Role: "dps"},
		{Name: "Feral", Slug: "feral", Role: "dps"},
		{Name: "Guardian", Slug: "guardian", Role: "tank"},
		{Name: "Restoration", Slug: "restoration", Role: "healer"},
	}},
	{Name: "Evoker", Slug: "evoker", Specs: []ClassSpec{
		{Name: "Augmentation", Slug: "augmentation", Role: "dps"},
		{Name: "Devastation", Slug: "devastation", Role: "dps"},
		{Name: "Preservation", Slug: "preservation", Role: "healer"},
	}},
	{Name: "Hunter", Slug: "hunter", Specs: []ClassSpec{
		{Name: "Beast Mastery", Slug: "beast-mastery", Role: "dps"},
		{Name: "Marksmanship", Slug: "marksmanship", Role: "dps"},
		{Name: "Survival", Slug: "survival", Role: "dps"},
	}},
	{Name: "Mage", Slug: "mage", Specs: []ClassSpec{
		{Name: "Arcane", Slug: "arcane", Role: "dps"},
		{Name: "Fire", Slug: "fire", Role: "dps"},
		{Name: "Frost", Slug: "frost", Role: "dps"},
	}},
	{Name: "Monk", Slug: "monk", Specs: []ClassSpec{
		{Name: "Brewmaster", Slug: "brewmaster", Role: "tank"},
		{Name: "Mistweaver", Slug: "mistweaver", Role: "healer"},
		{Name: "Windwalker", Slug: "windwalker", Role: "dps"},
	}},
	{Name: "Paladin", Slug: "paladin", Specs: []ClassSpec{
		{Name: "Holy", Slug: "holy", Role: "healer"},
		{Name: "Protection", Slug: "protection", Role: "tank"},
		{Name: "Retribution", Slug: "retribution", Role: "dps"},
	}},
	{Name: "Priest", Slug: "priest", Specs: []ClassSpec{
		{Name: "Discipline", Slug: "discipline", Role: "healer"},
		{Name: "Holy", Slug: "holy", Role: "healer"},
		{Name: "Shadow", Slug: "shadow", Role: "dps"},
	}},
	{Name: "Rogue", Slug: "rogue", Specs: []ClassSpec{
		{Name: "Assassination", Slug: "assassination", Role: "dps"},
		{Name: "Outlaw", Slug: "outlaw", Role: "dps"},
		{Name: "Subtlety", Slug: "subtlety", Role: "dps"},
	}},
	{Name: "Shaman", Slug: "shaman", Specs: []ClassSpec{
		{Name: "Elemental", Slug: "elemental", Role: "dps"},
		{Name: "Enhancement", Slug: "enhancement", Role: "dps"},
		{Name: "Restoration", Slug: "restoration", Role: "healer"},
	}},
	{Name: "Warlock", Slug: "warlock", Specs: []ClassSpec{
		{Name: "Affliction", Slug: "affliction", Role: "dps"},
		{Name: "Demonology", Slug: "demonology", Role: "dps"},
		{Name: "Destruction", Slug: "destruction", Role: "dps"},
	}},
	{Name: "Warrior", Slug: "warrior", Specs: []ClassSpec{
		{Name: "Arms", Slug: "arms", Role: "dps"},
		{Name: "Fury", Slug: "fury", Role: "dps"},
		{Name: "Protection", Slug: "protection", Role: "tank"},
	}},
}

// IcyVeinsURLs builds Icy Veins guide URLs for a class+spec.
// Note: Icy Veins uses "healing" for healers (not "healer").
func IcyVeinsURLs(classSlug string, spec ClassSpec) map[string]string {
	role := spec.Role
	if role == "healer" {
		role = "healing"
	}
	base := fmt.Sprintf("https://www.icy-veins.com/wow/%s-%s-pve-%s", spec.Slug, classSlug, role)

	// Hunter specs use "-spec-builds-pet-talents" instead of "-spec-builds-talents"
	talentSuffix := "-spec-builds-talents"
	if classSlug == "hunter" {
		talentSuffix = "-spec-builds-pet-talents"
	}

	return map[string]string{
		"gear":     base + "-gear-best-in-slot",
		"enchants": base + "-gems-enchants-consumables",
		"talents":  base + talentSuffix,
	}
}

// WowheadURLs builds Wowhead guide URLs for a class+spec (fallback).
func WowheadURLs(classSlug string, spec ClassSpec) map[string]string {
	// Wowhead uses slightly different URL format
	return map[string]string{
		"gear":     fmt.Sprintf("https://www.wowhead.com/guide/classes/%s/%s/bis-gear", classSlug, spec.Slug),
		"enchants": fmt.Sprintf("https://www.wowhead.com/guide/classes/%s/%s/enchants-gems-pve-%s", classSlug, spec.Slug, spec.Role),
		"talents":  fmt.Sprintf("https://www.wowhead.com/guide/classes/%s/%s/talent-builds-pve-%s", classSlug, spec.Slug, spec.Role),
	}
}

// FetchPage retrieves a URL with proper headers.
func FetchPage(url string) ([]byte, error) {
	client := &http.Client{Timeout: 30 * time.Second}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
	req.Header.Set("Accept-Language", "en-US,en;q=0.5")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d for %s", resp.StatusCode, url)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("reading body: %w", err)
	}
	return body, nil
}

// Delay waits the polite delay between requests.
func Delay() {
	time.Sleep(requestDelay)
}

// SpecData holds all parsed data for one specialization.
type SpecData struct {
	Name         string
	OverallGear  []GearItem
	RaidGear     []GearItem
	MythicGear   []GearItem
	Enchants     []EnchantItem
	Gems         []GemItem
	Consumables  []Consumable
	TalentBuilds    []TalentBuild
	TrinketRankings []TrinketRanking
}

type GearItem struct {
	Slot         string
	ItemID       int
	Name         string
	Source       string
	BonusIDs     string   // colon-separated bonus IDs (e.g. "10356:1540")
	Ilvl         int      // item level from source (0 if unknown)
	TooltipLines []string // pre-formatted tooltip lines from Wowhead
}

type EnchantItem struct {
	Slot   string
	ItemID int
	Name   string
}

type GemItem struct {
	ItemID int
	Name   string
	Note   string
}

type Consumable struct {
	Type   string
	ItemID int
	Name   string
}

type TalentBuild struct {
	Name    string
	Code    string
	Context string
}

type TrinketRanking struct {
	Tier   string
	ItemID int
	Name   string
}
