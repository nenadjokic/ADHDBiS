package scraper

import (
	"bytes"
	"fmt"
	"regexp"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// statNames are the secondary/primary stats we look for in stat priority text.
var statNames = []string{
	"Haste", "Critical Strike", "Crit", "Mastery", "Versatility",
	"Intellect", "Strength", "Agility", "Stamina",
}

// statPriorityRe matches stat priority patterns like "Haste > Crit = Mastery > Versatility"
var statPriorityRe = regexp.MustCompile(`(?i)((?:Haste|Critical Strike|Crit|Mastery|Versatility|Intellect|Strength|Agility|Stamina)\s*(?:[>>=≥~≈]+\s*(?:Haste|Critical Strike|Crit|Mastery|Versatility|Intellect|Strength|Agility|Stamina)\s*){1,})`)

// ParseWowheadStatPriority extracts stat priority from a Wowhead guide page.
// Wowhead uses BBCode-like markup, so we search the raw markup text for stat priority patterns.
func ParseWowheadStatPriority(body []byte) string {
	markup := extractMarkup(body)
	if markup == "" {
		return ""
	}

	// Look for stat priority text in the markup
	// First try near headings mentioning "stat"
	lines := strings.Split(markup, "\n")
	nearStatHeading := false
	for _, line := range lines {
		lineLower := strings.ToLower(line)
		if strings.Contains(lineLower, "[h2") || strings.Contains(lineLower, "[h3") || strings.Contains(lineLower, "[h4") {
			nearStatHeading = strings.Contains(lineLower, "stat")
			continue
		}
		if nearStatHeading && containsStatPriority(line) {
			result := extractStatPriority(line)
			if result != "" {
				logf("    Found stat priority (Wowhead heading): %s\n", result)
				return result
			}
		}
	}

	// Fallback: scan all lines for the regex pattern
	for _, line := range lines {
		if containsStatPriority(line) {
			result := extractStatPriority(line)
			if result != "" {
				logf("    Found stat priority (Wowhead fallback): %s\n", result)
				return result
			}
		}
	}

	return ""
}

// ParseStatPriority extracts stat priority from an Icy Veins enchants/gems page.
// It looks for headings containing "Stat" and extracts priority text from nearby content.
func ParseStatPriority(body []byte) string {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(body))
	if err != nil {
		return ""
	}

	// Strategy 1: Look for headings with "Stat" in text, then grab the next paragraph/list
	var result string
	doc.Find("h2, h3, h4").Each(func(i int, heading *goquery.Selection) {
		if result != "" {
			return
		}
		text := strings.ToLower(heading.Text())
		if !strings.Contains(text, "stat") {
			return
		}
		// Check siblings after this heading for stat priority text
		heading.NextAll().EachWithBreak(func(j int, sib *goquery.Selection) bool {
			sibTag := goquery.NodeName(sib)
			// Stop at next heading
			if sibTag == "h2" || sibTag == "h3" || sibTag == "h4" {
				return false
			}
			sibText := strings.TrimSpace(sib.Text())
			// Look for text containing > separators and stat names
			if containsStatPriority(sibText) {
				result = extractStatPriority(sibText)
				if result != "" {
					return false
				}
			}
			return true
		})
	})

	if result != "" {
		logf("    Found stat priority: %s\n", result)
		return result
	}

	// Strategy 2: Scan all text for the regex pattern
	doc.Find("p, li, ol, td").Each(func(i int, el *goquery.Selection) {
		if result != "" {
			return
		}
		text := strings.TrimSpace(el.Text())
		if containsStatPriority(text) {
			result = extractStatPriority(text)
		}
	})

	if result != "" {
		logf("    Found stat priority (fallback): %s\n", result)
	}
	return result
}

// containsStatPriority checks if text looks like a stat priority string.
func containsStatPriority(text string) bool {
	if !strings.Contains(text, ">") && !strings.Contains(text, "≥") {
		return false
	}
	statCount := 0
	textLower := strings.ToLower(text)
	for _, stat := range statNames {
		if strings.Contains(textLower, strings.ToLower(stat)) {
			statCount++
		}
	}
	return statCount >= 3
}

// extractStatPriority pulls out the stat priority substring from a longer text.
func extractStatPriority(text string) string {
	// Try regex first
	m := statPriorityRe.FindString(text)
	if m != "" {
		return strings.TrimSpace(m)
	}

	// Fallback: find the line containing > and stat names
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if containsStatPriority(line) && len(line) < 200 {
			return line
		}
	}
	return ""
}

// ParseEnchants parses enchants, gems, and consumables from an Icy Veins page.
// Structure:
//   - Enchants: <table class="enchants"> with Slot | Enchantment columns
//   - Gems: <span data-wowhead="item=XXXXX"> in section with "gems" heading
//   - Consumables: organized by sub-headings (Flasks, Potions, Food, Weapon Runes, Augment Runes)
func ParseEnchants(body []byte) (enchants []EnchantItem, gems []GemItem, consumables []Consumable, err error) {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(body))
	if err != nil {
		return nil, nil, nil, fmt.Errorf("parsing HTML: %w", err)
	}

	// === ENCHANTS ===
	// Icy Veins uses <table class="enchants"> with td:first = Slot, td:second = enchant items
	doc.Find("table.enchants tr").Each(func(i int, tr *goquery.Selection) {
		tds := tr.Find("td")
		if tds.Length() < 2 {
			return
		}

		slotRaw := strings.TrimSpace(tds.Eq(0).Text())
		slot := NormalizeSlot(slotRaw)
		if slot == "" || slot == "Slot" {
			return
		}

		// Get first item in the enchant cell (primary recommendation)
		tds.Eq(1).Find("span[data-wowhead]").First().Each(func(j int, span *goquery.Selection) {
			wh, _ := span.Attr("data-wowhead")
			if !strings.Contains(wh, "item=") {
				return
			}
			itemID := extractItemID(wh)
			name := strings.TrimSpace(span.Text())
			if itemID > 0 && name != "" {
				enchants = append(enchants, EnchantItem{Slot: slot, ItemID: itemID, Name: name})
			}
		})
	})

	// Fallback: if no enchants table found, search all tables
	if len(enchants) == 0 {
		doc.Find("table tr").Each(func(i int, tr *goquery.Selection) {
			tds := tr.Find("td")
			if tds.Length() < 2 {
				return
			}
			slotRaw := strings.TrimSpace(tds.Eq(0).Text())
			slotLower := strings.ToLower(slotRaw)
			enchantSlots := []string{"helm", "head", "shoulders", "chest", "legs", "feet", "rings", "ring", "weapon", "wrist", "back", "cloak"}
			isEnchantSlot := false
			for _, es := range enchantSlots {
				if strings.Contains(slotLower, es) {
					isEnchantSlot = true
					break
				}
			}
			if !isEnchantSlot {
				return
			}

			slot := NormalizeSlot(slotRaw)
			tds.Eq(1).Find("span[data-wowhead]").First().Each(func(j int, span *goquery.Selection) {
				wh, _ := span.Attr("data-wowhead")
				if !strings.Contains(wh, "item=") {
					return
				}
				itemID := extractItemID(wh)
				name := strings.TrimSpace(span.Text())
				if itemID > 0 && name != "" {
					enchants = append(enchants, EnchantItem{Slot: slot, ItemID: itemID, Name: name})
				}
			})
		})
	}

	// === GEMS ===
	// Gems are in sections with "gem" in the heading, using span[data-wowhead="item=XXXXX"]
	// Epic gems are listed first (unique), then rare gems
	inGemSection := false
	inEnchantSection := false
	inConsumableSection := false

	doc.Find("h2, h3, span[data-wowhead]").Each(func(i int, s *goquery.Selection) {
		tag := goquery.NodeName(s)

		if tag == "h2" || tag == "h3" {
			text := strings.ToLower(s.Text())
			inGemSection = strings.Contains(text, "gem")
			inEnchantSection = strings.Contains(text, "enchant")
			inConsumableSection = strings.Contains(text, "consumable") || strings.Contains(text, "flask") ||
				strings.Contains(text, "potion") || strings.Contains(text, "food") || strings.Contains(text, "rune")
			_ = inEnchantSection // Used for context only
			return
		}

		if !inGemSection || inConsumableSection {
			return
		}

		wh, exists := s.Attr("data-wowhead")
		if !exists || !strings.Contains(wh, "item=") {
			return
		}
		itemID := extractItemID(wh)
		name := strings.TrimSpace(s.Text())
		if itemID == 0 || name == "" {
			return
		}

		// Check quality class for uniqueness hint
		note := ""
		class, _ := s.Attr("class")
		if strings.Contains(class, "q4") {
			note = "unique-equipped"
		}

		// Avoid duplicates
		isDupe := false
		for _, g := range gems {
			if g.ItemID == itemID {
				isDupe = true
				break
			}
		}
		if !isDupe {
			gems = append(gems, GemItem{ItemID: itemID, Name: name, Note: note})
		}
	})

	// === CONSUMABLES ===
	// Organized by sub-sections: Flasks, Potions, Food, Weapon Runes, Augment Runes
	currentType := ""
	doc.Find("h3, h2").Each(func(i int, heading *goquery.Selection) {
		text := strings.ToLower(heading.Text())
		headingID, _ := heading.Attr("id")
		headingIDLower := strings.ToLower(headingID)

		if strings.Contains(text, "flask") || strings.Contains(headingIDLower, "flask") {
			currentType = "Flask"
		} else if strings.Contains(text, "potion") || strings.Contains(headingIDLower, "potion") {
			currentType = "Potion"
		} else if strings.Contains(text, "food") || strings.Contains(headingIDLower, "food") {
			currentType = "Food"
		} else if strings.Contains(text, "weapon rune") || strings.Contains(headingIDLower, "weapon-rune") {
			currentType = "Weapon Rune"
		} else if strings.Contains(text, "augment") || strings.Contains(headingIDLower, "augment") {
			currentType = "Rune"
		} else {
			return
		}

		// Find items in sibling elements after this heading
		heading.NextAll().EachWithBreak(func(j int, sib *goquery.Selection) bool {
			sibTag := goquery.NodeName(sib)
			// Stop at next heading
			if sibTag == "h2" || sibTag == "h3" {
				return false
			}

			sib.Find("span[data-wowhead]").Each(func(k int, span *goquery.Selection) {
				wh, _ := span.Attr("data-wowhead")
				if !strings.Contains(wh, "item=") {
					return
				}
				itemID := extractItemID(wh)
				name := strings.TrimSpace(span.Text())
				if itemID > 0 && name != "" {
					// Avoid duplicates
					isDupe := false
					for _, c := range consumables {
						if c.ItemID == itemID {
							isDupe = true
							break
						}
					}
					if !isDupe {
						consumables = append(consumables, Consumable{
							Type: currentType, ItemID: itemID, Name: name,
						})
					}
				}
			})
			return true
		})
	})

	// Fallback: if no structured consumables found, scan all items in consumable section
	if len(consumables) == 0 {
		inConsSection := false
		doc.Find("h2, p, ul").Each(func(i int, el *goquery.Selection) {
			tag := goquery.NodeName(el)
			if tag == "h2" {
				text := strings.ToLower(el.Text())
				inConsSection = strings.Contains(text, "consumable")
				return
			}
			if !inConsSection {
				return
			}
			el.Find("span[data-wowhead]").Each(func(j int, span *goquery.Selection) {
				wh, _ := span.Attr("data-wowhead")
				if !strings.Contains(wh, "item=") {
					return
				}
				itemID := extractItemID(wh)
				name := strings.TrimSpace(span.Text())
				if itemID > 0 && name != "" {
					// Guess type from name
					cType := "Other"
					nameLower := strings.ToLower(name)
					if strings.Contains(nameLower, "flask") {
						cType = "Flask"
					} else if strings.Contains(nameLower, "potion") || strings.Contains(nameLower, "potential") {
						cType = "Potion"
					} else if strings.Contains(nameLower, "feast") || strings.Contains(nameLower, "roast") || strings.Contains(nameLower, "food") {
						cType = "Food"
					} else if strings.Contains(nameLower, "rune") {
						cType = "Rune"
					} else if strings.Contains(nameLower, "oil") {
						cType = "Weapon Rune"
					}
					consumables = append(consumables, Consumable{Type: cType, ItemID: itemID, Name: name})
				}
			})
		})
	}

	logf("    Found %d enchants, %d gems, %d consumables\n", len(enchants), len(gems), len(consumables))
	return enchants, gems, consumables, nil
}
