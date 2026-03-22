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
				name := strings.TrimSpace(span.Text())
				source := ""
				if tds.Length() >= 3 {
					source = strings.TrimSpace(tds.Eq(2).Text())
				}
				if itemID > 0 && name != "" {
					raid = append(raid, GearItem{Slot: slot, ItemID: itemID, Name: name, Source: source})
				}
			})
		})
		mythic = raid
	}

	logf("    Found %d raid items, %d M+ items\n", len(raid), len(mythic))
	return raid, mythic, nil
}
