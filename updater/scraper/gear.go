package scraper

import (
	"bytes"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// NormalizeSlot maps various slot name variations to canonical names.
func NormalizeSlot(raw string) string {
	s := strings.TrimSpace(raw)
	s = strings.ToLower(s)

	mapping := map[string]string{
		"head": "Head", "helm": "Head",
		"neck": "Neck", "necklace": "Neck",
		"shoulder": "Shoulders", "shoulders": "Shoulders",
		"back": "Back", "cloak": "Back", "cape": "Back",
		"chest": "Chest", "robe": "Chest",
		"wrist": "Wrist", "wrists": "Wrist", "bracer": "Wrist", "bracers": "Wrist",
		"hands": "Hands", "gloves": "Hands",
		"waist": "Waist", "belt": "Waist",
		"legs": "Legs",
		"feet": "Feet", "boots": "Feet",
		"finger": "Finger1", "ring": "Finger1", "rings": "Finger1",
		"ring #1": "Finger1", "ring #2": "Finger2",
		"trinket": "Trinket1",
		"trinket #1": "Trinket1", "trinket #2": "Trinket2",
		"weapon": "Weapon", "main hand": "Weapon", "mainhand": "Weapon",
		"off-hand": "OffHand", "offhand": "OffHand", "off hand": "OffHand",
	}

	if mapped, ok := mapping[s]; ok {
		return mapped
	}
	if len(s) > 0 {
		return strings.ToUpper(s[:1]) + s[1:]
	}
	return s
}

var itemIDRegex = regexp.MustCompile(`item=(\d+)`)
var bonusRegex = regexp.MustCompile(`bonus=([0-9:]+)`)
var ilvlRegex = regexp.MustCompile(`ilvl=(\d+)`)

func extractItemID(attr string) int {
	matches := itemIDRegex.FindStringSubmatch(attr)
	if len(matches) >= 2 {
		id, err := strconv.Atoi(matches[1])
		if err == nil {
			return id
		}
	}
	return 0
}

// extractBonusIDs extracts bonus IDs from a data-wowhead attribute (e.g. "item=228411&bonus=10356:1540&ilvl=639")
func extractBonusIDs(attr string) string {
	matches := bonusRegex.FindStringSubmatch(attr)
	if len(matches) >= 2 {
		return matches[1]
	}
	return ""
}

// extractIlvl extracts item level from a data-wowhead attribute
func extractIlvl(attr string) int {
	matches := ilvlRegex.FindStringSubmatch(attr)
	if len(matches) >= 2 {
		v, err := strconv.Atoi(matches[1])
		if err == nil {
			return v
		}
	}
	return 0
}

// ParseGear parses BiS gear from an Icy Veins page.
// Icy Veins structure: image_block tabs with area_1 (Overall), area_2 (M+), area_3 (Raid).
// Items use <span data-wowhead="item=XXXXX"> pattern.
func ParseGear(body []byte) (raid []GearItem, mythic []GearItem, err error) {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(body))
	if err != nil {
		return nil, nil, fmt.Errorf("parsing HTML: %w", err)
	}

	// Identify which area_N maps to raid/mythicplus/overall
	areaMapping := map[string]string{}
	doc.Find(".image_block_header_buttons span").Each(func(i int, s *goquery.Selection) {
		id, exists := s.Attr("id")
		if !exists {
			return
		}
		text := strings.ToLower(s.Text())
		areaID := strings.TrimSuffix(id, "_button")

		if strings.Contains(text, "raid") {
			areaMapping[areaID] = "raid"
		} else if strings.Contains(text, "mythic") || strings.Contains(text, "m+") {
			areaMapping[areaID] = "mythicplus"
		} else if strings.Contains(text, "overall") {
			areaMapping[areaID] = "overall"
		}
	})

	parseTable := func(areaID string) []GearItem {
		var items []GearItem
		selector := fmt.Sprintf("#%s table tr", areaID)
		doc.Find(selector).Each(func(i int, tr *goquery.Selection) {
			tds := tr.Find("td")
			if tds.Length() < 2 {
				return
			}

			slotRaw := strings.TrimSpace(tds.Eq(0).Text())
			slot := NormalizeSlot(slotRaw)
			if slot == "" {
				return
			}

			tds.Eq(1).Find("span[data-wowhead]").Each(func(j int, span *goquery.Selection) {
				wh, _ := span.Attr("data-wowhead")
				if !strings.Contains(wh, "item=") {
					return
				}
				itemID := extractItemID(wh)
				name := strings.TrimSpace(span.Text())
				if itemID == 0 || name == "" {
					return
				}

				bonusIDs := extractBonusIDs(wh)
				ilvl := extractIlvl(wh)

				source := ""
				if tds.Length() >= 3 {
					source = strings.TrimSpace(tds.Eq(2).Text())
				}

				// Handle second item in same slot cell
				actualSlot := slot
				if j > 0 {
					if slot == "Finger1" {
						actualSlot = "Finger2"
					} else if slot == "Trinket1" {
						actualSlot = "Trinket2"
					}
				}

				items = append(items, GearItem{
					Slot: actualSlot, ItemID: itemID, Name: name, Source: source,
					BonusIDs: bonusIDs, Ilvl: ilvl,
				})
			})
		})
		return items
	}

	// Parse by area mapping
	for areaID, areaType := range areaMapping {
		items := parseTable(areaID)
		switch areaType {
		case "raid":
			raid = items
		case "mythicplus":
			mythic = items
		case "overall":
			if len(raid) == 0 {
				raid = items
			}
			if len(mythic) == 0 {
				mythic = items
			}
		}
	}

	// Fallback: try standard area IDs
	if len(raid) == 0 && len(mythic) == 0 {
		raid = parseTable("area_3")
		mythic = parseTable("area_2")
		if len(raid) == 0 {
			raid = parseTable("area_1")
		}
		if len(mythic) == 0 {
			mythic = parseTable("area_1")
		}
	}

	// Last resort: any table with gear-slot first columns
	if len(raid) == 0 {
		validSlots := map[string]bool{
			"Head": true, "Neck": true, "Shoulders": true, "Back": true,
			"Chest": true, "Wrist": true, "Hands": true, "Waist": true,
			"Legs": true, "Feet": true, "Finger1": true, "Finger2": true,
			"Trinket1": true, "Trinket2": true, "Weapon": true, "OffHand": true,
		}
		doc.Find("table tr").Each(func(i int, tr *goquery.Selection) {
			tds := tr.Find("td")
			if tds.Length() < 2 {
				return
			}
			slot := NormalizeSlot(strings.TrimSpace(tds.Eq(0).Text()))
			if !validSlots[slot] {
				return
			}
			tds.Eq(1).Find("span[data-wowhead]").Each(func(j int, span *goquery.Selection) {
				wh, _ := span.Attr("data-wowhead")
				if !strings.Contains(wh, "item=") {
					return
				}
				itemID := extractItemID(wh)
				bonusIDs := extractBonusIDs(wh)
				ilvl := extractIlvl(wh)
				name := strings.TrimSpace(span.Text())
				source := ""
				if tds.Length() >= 3 {
					source = strings.TrimSpace(tds.Eq(2).Text())
				}
				if itemID > 0 && name != "" {
					raid = append(raid, GearItem{Slot: slot, ItemID: itemID, Name: name, Source: source, BonusIDs: bonusIDs, Ilvl: ilvl})
				}
			})
		})
		mythic = raid
	}

	logf("    Found %d raid items, %d M+ items\n", len(raid), len(mythic))
	return raid, mythic, nil
}

// tierRegex matches tier labels like "S Tier", "A Tier", etc.
var tierRegex = regexp.MustCompile(`(?i)^([SABCD])\s*Tier`)

// ParseTrinketRankings extracts trinket tier rankings from an Icy Veins BiS gear page.
// Returns an empty slice (not error) if no rankings are found.
func ParseTrinketRankings(body []byte) ([]TrinketRanking, error) {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("parsing HTML: %w", err)
	}

	var rankings []TrinketRanking
	tierOrder := []string{"S", "A", "B", "C", "D"}

	// Strategy 1: Find elements containing tier text patterns followed by item links.
	// Icy Veins uses various structures - look for text nodes with "X Tier" followed by
	// sibling/child spans with data-wowhead item attributes.
	doc.Find("h2, h3, h4, h5, strong, b, p, td, th, li, div, span").Each(func(i int, s *goquery.Selection) {
		text := strings.TrimSpace(s.Text())
		// Only match short text that looks like a tier label (avoid matching huge parent containers)
		if len(text) > 30 {
			return
		}
		matches := tierRegex.FindStringSubmatch(text)
		if len(matches) < 2 {
			return
		}
		tier := strings.ToUpper(matches[1])

		// Look for item links in the same parent or next sibling elements
		parent := s.Parent()
		if parent == nil {
			return
		}

		// Check siblings and parent for data-wowhead items near this tier label
		var found bool
		parent.Find("span[data-wowhead], a[data-wowhead]").Each(func(j int, item *goquery.Selection) {
			wh, _ := item.Attr("data-wowhead")
			if !strings.Contains(wh, "item=") {
				return
			}
			itemID := extractItemID(wh)
			name := strings.TrimSpace(item.Text())
			if itemID > 0 && name != "" {
				rankings = append(rankings, TrinketRanking{Tier: tier, ItemID: itemID, Name: name})
				found = true
			}
		})

		// If not found in parent, check next siblings
		if !found {
			nextEl := s.Parent().Next()
			for k := 0; k < 5 && nextEl.Length() > 0; k++ {
				nextText := strings.TrimSpace(nextEl.Text())
				// Stop if we hit another tier label
				if tierRegex.MatchString(nextText) && len(nextText) <= 30 {
					break
				}
				nextEl.Find("span[data-wowhead], a[data-wowhead]").Each(func(j int, item *goquery.Selection) {
					wh, _ := item.Attr("data-wowhead")
					if !strings.Contains(wh, "item=") {
						return
					}
					itemID := extractItemID(wh)
					name := strings.TrimSpace(item.Text())
					if itemID > 0 && name != "" {
						rankings = append(rankings, TrinketRanking{Tier: tier, ItemID: itemID, Name: name})
					}
				})
				nextEl = nextEl.Next()
			}
		}
	})

	// Strategy 2: Look for table rows with tier labels in first column
	if len(rankings) == 0 {
		doc.Find("table tr").Each(func(i int, tr *goquery.Selection) {
			tds := tr.Find("td, th")
			if tds.Length() < 2 {
				return
			}
			firstCell := strings.TrimSpace(tds.Eq(0).Text())
			matches := tierRegex.FindStringSubmatch(firstCell)
			if len(matches) < 2 {
				return
			}
			tier := strings.ToUpper(matches[1])

			// Items are in remaining cells
			tds.Each(func(j int, td *goquery.Selection) {
				if j == 0 {
					return
				}
				td.Find("span[data-wowhead], a[data-wowhead]").Each(func(k int, item *goquery.Selection) {
					wh, _ := item.Attr("data-wowhead")
					if !strings.Contains(wh, "item=") {
						return
					}
					itemID := extractItemID(wh)
					name := strings.TrimSpace(item.Text())
					if itemID > 0 && name != "" {
						rankings = append(rankings, TrinketRanking{Tier: tier, ItemID: itemID, Name: name})
					}
				})
			})
		})
	}

	// Deduplicate by itemID (keep first occurrence)
	seen := map[int]bool{}
	var deduped []TrinketRanking
	for _, r := range rankings {
		if !seen[r.ItemID] {
			seen[r.ItemID] = true
			deduped = append(deduped, r)
		}
	}
	rankings = deduped

	// Sort by tier order: S -> A -> B -> C -> D
	tierIdx := map[string]int{}
	for i, t := range tierOrder {
		tierIdx[t] = i
	}
	// Stable sort preserving order within same tier
	for i := 1; i < len(rankings); i++ {
		for j := i; j > 0 && tierIdx[rankings[j].Tier] < tierIdx[rankings[j-1].Tier]; j-- {
			rankings[j], rankings[j-1] = rankings[j-1], rankings[j]
		}
	}

	logf("    Found %d trinket rankings\n", len(rankings))
	return rankings, nil
}
