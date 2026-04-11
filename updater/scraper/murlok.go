package scraper

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

// Murlok.io API response structures

type murlokGuide struct {
	UpdatedAt  string            `json:"UpdatedAt"`
	Characters []murlokCharacter `json:"Characters"`
}

type murlokCharacter struct {
	RatingMM          int               `json:"RatingMM"`
	EquippedItemLevel int               `json:"EquippedItemLevel"`
	Equipment         murlokEquipment   `json:"Equipment"`
	TalentsCode       string            `json:"TalentsCode"`
	Haste             int               `json:"Haste"`
	Crit              int               `json:"Crit"`
	Mastery           int               `json:"Mastery"`
	Versatility       int               `json:"Versatility"`
}

type murlokEquipment struct {
	Items []murlokItem `json:"Items"`
}

type murlokItem struct {
	ItemID       int                `json:"ItemID"`
	Name         string             `json:"Name"`
	Slot         string             `json:"Slot"`
	ILevel       int                `json:"ILevel"`
	Enchantments []murlokEnchant    `json:"Enchantments"`
	Gems         []murlokGem        `json:"Gems"`
}

type murlokEnchant struct {
	ID          int    `json:"ID"`
	ItemID      int    `json:"ItemID"`
	Slot        string `json:"Slot"`
	Description string `json:"Description"`
}

type murlokGem struct {
	ItemID int    `json:"ItemID"`
	Name   string `json:"Name"`
	Type   string `json:"Type"`
}

// MurlokURL builds the Murlok.io API URL for a class+spec (M+ only).
func MurlokURL(classSlug string, spec ClassSpec) string {
	return fmt.Sprintf("https://murlok.io/api/guides/%s/%s/m+", classSlug, spec.Slug)
}

// murlokSlotMap maps Murlok.io slot names to our canonical slot names.
var murlokSlotMap = map[string]string{
	"head":      "Head",
	"neck":      "Neck",
	"shoulders": "Shoulders",
	"chest":     "Chest",
	"waist":     "Waist",
	"legs":      "Legs",
	"feet":      "Feet",
	"wrist":     "Wrist",
	"hands":     "Hands",
	"ring-1":    "Ring",
	"ring-2":    "Ring",
	"trinket-1": "Trinket",
	"trinket-2": "Trinket",
	"back":      "Back",
	"main-hand": "MainHand",
	"off-hand":  "OffHand",
}

// ParseMurlok parses the Murlok.io API JSON response and aggregates gear from top players.
// It returns a SpecData with M+ gear (most popular items per slot), enchants, gems, and talents.
func ParseMurlok(body []byte) (*SpecData, error) {
	var guide murlokGuide
	if err := json.Unmarshal(body, &guide); err != nil {
		return nil, fmt.Errorf("parsing Murlok.io JSON: %w", err)
	}

	if len(guide.Characters) == 0 {
		return nil, fmt.Errorf("no character data from Murlok.io")
	}

	specData := &SpecData{
		SourceLastModified: guide.UpdatedAt,
	}

	// Aggregate items per slot across all characters
	// Use the raw Murlok slot name as key (ring-1, ring-2 stay separate)
	type itemCount struct {
		item  GearItem
		count int
	}
	slotItems := make(map[string]map[int]*itemCount) // murlokSlot -> itemID -> count

	// Aggregate enchants per slot
	type enchCount struct {
		enchant EnchantItem
		count   int
	}
	slotEnchants := make(map[string]map[int]*enchCount) // slot -> enchantItemID -> count

	// Aggregate gems
	type gemCount struct {
		gem   GemItem
		count int
	}
	gemCounts := make(map[int]*gemCount) // gemItemID -> count

	// Aggregate talent codes
	talentCounts := make(map[string]int) // code -> count

	// Aggregate stat totals for priority derivation
	var totalHaste, totalCrit, totalMastery, totalVers int

	for _, char := range guide.Characters {
		// Stats
		totalHaste += char.Haste
		totalCrit += char.Crit
		totalMastery += char.Mastery
		totalVers += char.Versatility

		// Talents
		if char.TalentsCode != "" {
			talentCounts[char.TalentsCode]++
		}

		// Equipment
		for _, item := range char.Equipment.Items {
			if item.ItemID == 0 || item.Slot == "" {
				continue
			}
			slot, ok := murlokSlotMap[item.Slot]
			if !ok {
				continue
			}

			if slotItems[item.Slot] == nil {
				slotItems[item.Slot] = make(map[int]*itemCount)
			}
			if ic, exists := slotItems[item.Slot][item.ItemID]; exists {
				ic.count++
				// Keep highest ilvl seen
				if item.ILevel > ic.item.Ilvl {
					ic.item.Ilvl = item.ILevel
				}
			} else {
				slotItems[item.Slot][item.ItemID] = &itemCount{
					item: GearItem{
						Slot:   slot,
						ItemID: item.ItemID,
						Name:   item.Name,
						Ilvl:   item.ILevel,
						Source:  "Top Players (Murlok.io)",
					},
					count: 1,
				}
			}

			// Enchants on this item
			for _, ench := range item.Enchantments {
				// Use ItemID if available, otherwise use enchant ID as identifier
				enchID := ench.ItemID
				if enchID == 0 {
					enchID = ench.ID
				}
				if enchID == 0 {
					continue
				}
				enchSlot := slot
				if slotEnchants[enchSlot] == nil {
					slotEnchants[enchSlot] = make(map[int]*enchCount)
				}
				enchName := cleanEnchantDesc(ench.Description)
				if ec, exists := slotEnchants[enchSlot][enchID]; exists {
					ec.count++
				} else {
					slotEnchants[enchSlot][enchID] = &enchCount{
						enchant: EnchantItem{
							Slot:   enchSlot,
							ItemID: enchID,
							Name:   enchName,
						},
						count: 1,
					}
				}
			}

			// Gems
			for _, gem := range item.Gems {
				if gem.ItemID == 0 {
					continue
				}
				if gc, exists := gemCounts[gem.ItemID]; exists {
					gc.count++
				} else {
					gemCounts[gem.ItemID] = &gemCount{
						gem: GemItem{
							ItemID: gem.ItemID,
							Name:   gem.Name,
						},
						count: 1,
					}
				}
			}
		}
	}

	// Build M+ gear list: pick most popular item per slot
	var mGear []GearItem
	for _, items := range slotItems {
		// Sort by popularity (highest count first)
		sorted := make([]*itemCount, 0, len(items))
		for _, ic := range items {
			sorted = append(sorted, ic)
		}
		sort.Slice(sorted, func(i, j int) bool {
			return sorted[i].count > sorted[j].count
		})
		if len(sorted) > 0 {
			best := sorted[0]
			pct := best.count * 100 / len(guide.Characters)
			best.item.Source = fmt.Sprintf("Top Players (%d%%)", pct)
			mGear = append(mGear, best.item)
		}
	}
	// Sort gear by slot order for consistent output
	slotOrder := map[string]int{
		"Head": 1, "Neck": 2, "Shoulders": 3, "Back": 4, "Chest": 5,
		"Wrist": 6, "Hands": 7, "Waist": 8, "Legs": 9, "Feet": 10,
		"Ring": 11, "Trinket": 12, "MainHand": 13, "OffHand": 14,
	}
	sort.Slice(mGear, func(i, j int) bool {
		return slotOrder[mGear[i].Slot] < slotOrder[mGear[j].Slot]
	})
	specData.MythicGear = mGear

	// Build enchant list: most popular per slot
	var enchants []EnchantItem
	for _, ecMap := range slotEnchants {
		sorted := make([]*enchCount, 0, len(ecMap))
		for _, ec := range ecMap {
			sorted = append(sorted, ec)
		}
		sort.Slice(sorted, func(i, j int) bool {
			return sorted[i].count > sorted[j].count
		})
		if len(sorted) > 0 {
			enchants = append(enchants, sorted[0].enchant)
		}
	}
	specData.Enchants = enchants

	// Build gem list: top 3 most popular
	gemSorted := make([]*gemCount, 0, len(gemCounts))
	for _, gc := range gemCounts {
		gemSorted = append(gemSorted, gc)
	}
	sort.Slice(gemSorted, func(i, j int) bool {
		return gemSorted[i].count > gemSorted[j].count
	})
	var gems []GemItem
	for i, gc := range gemSorted {
		if i >= 3 {
			break
		}
		gems = append(gems, gc.gem)
	}
	specData.Gems = gems

	// Build talent list: top 3 most popular builds
	type talentEntry struct {
		code  string
		count int
	}
	talentSorted := make([]talentEntry, 0, len(talentCounts))
	for code, count := range talentCounts {
		talentSorted = append(talentSorted, talentEntry{code, count})
	}
	sort.Slice(talentSorted, func(i, j int) bool {
		return talentSorted[i].count > talentSorted[j].count
	})
	var talents []TalentBuild
	for i, te := range talentSorted {
		if i >= 3 {
			break
		}
		pct := te.count * 100 / len(guide.Characters)
		name := fmt.Sprintf("M+ Build #%d (%d%% of top players)", i+1, pct)
		talents = append(talents, TalentBuild{
			Name:    name,
			Code:    te.code,
			Context: "mythicplus",
		})
	}
	specData.TalentBuilds = talents

	// Derive stat priority from aggregated stats
	n := len(guide.Characters)
	if n > 0 {
		type statVal struct {
			name string
			avg  int
		}
		stats := []statVal{
			{"Haste", totalHaste / n},
			{"Critical Strike", totalCrit / n},
			{"Mastery", totalMastery / n},
			{"Versatility", totalVers / n},
		}
		sort.Slice(stats, func(i, j int) bool {
			return stats[i].avg > stats[j].avg
		})
		parts := make([]string, len(stats))
		for i, s := range stats {
			parts[i] = s.name
		}
		specData.StatPriority = strings.Join(parts, " > ")
	}

	return specData, nil
}

// cleanEnchantDesc strips the "Enchanted: " prefix from Murlok.io enchant descriptions.
func cleanEnchantDesc(desc string) string {
	desc = strings.TrimSpace(desc)
	if strings.HasPrefix(desc, "Enchanted: ") {
		desc = desc[len("Enchanted: "):]
	}
	return strings.TrimSpace(desc)
}
