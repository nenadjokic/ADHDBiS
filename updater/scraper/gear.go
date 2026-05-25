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
//
// Modern Icy Veins (post Astro redesign) layout:
//
//	<div class="image_block_header_buttons">
//	  <span id="bis_0_0_button">Overall</span>
//	  <span id="bis_0_1_button">Mythic+</span>
//	  <span id="bis_0_2_button">Raid</span>
//	</div>
//	<div id="bis_0_0"><div class="bis_items_grid">
//	   <div class="bis_item">
//	     <span class="spell_icon_span" data-wowhead="item=ID&bonus=Y">
//	       <img...><span data-wowhead="item=ID..." class="qN">NAME</span>
//	     </span>
//	     <span class="bis_item_slot">SLOT</span>
//	     <div class="bis_item_footer"><span class="bis_item_drop"><a>SOURCE</a></span></div>
//	   </div>
//	   ...
//	</div></div>
//
// Legacy layout (pre-redesign) used <table> rows inside area_N divs. We keep
// a table-based fallback so older or differently structured pages still parse.
func ParseGear(body []byte) (raid []GearItem, mythic []GearItem, overall []GearItem, err error) {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(body))
	if err != nil {
		return nil, nil, nil, fmt.Errorf("parsing HTML: %w", err)
	}

	// Map section IDs (bis_0_N or area_N) to category by reading button labels.
	sectionMapping := map[string]string{} // sectionID -> overall|mythicplus|raid
	doc.Find(".image_block_header_buttons span[id]").Each(func(i int, s *goquery.Selection) {
		id, _ := s.Attr("id")
		if !strings.HasSuffix(id, "_button") {
			return
		}
		sectionID := strings.TrimSuffix(id, "_button")
		text := strings.ToLower(strings.TrimSpace(s.Text()))
		switch {
		case strings.Contains(text, "raid"):
			sectionMapping[sectionID] = "raid"
		case strings.Contains(text, "mythic"), strings.Contains(text, "m+"):
			sectionMapping[sectionID] = "mythicplus"
		case strings.Contains(text, "overall"):
			sectionMapping[sectionID] = "overall"
		}
	})

	// parseBisGrid parses .bis_item cards inside a #sectionID container.
	parseBisGrid := func(sectionID string) []GearItem {
		var items []GearItem
		fingerCount := 0
		trinketCount := 0
		doc.Find(fmt.Sprintf("#%s .bis_item", sectionID)).Each(func(i int, card *goquery.Selection) {
			slotRaw := strings.TrimSpace(card.Find(".bis_item_slot").First().Text())
			slot := NormalizeSlot(slotRaw)
			if slot == "" {
				return
			}

			// Pick the inner data-wowhead span (the one with the readable name -
			// class starts with "q" + quality digit, e.g. q3, q4).
			var itemID, ilvl int
			var bonusIDs, name string
			card.Find("span[data-wowhead]").EachWithBreak(func(j int, span *goquery.Selection) bool {
				cls, _ := span.Attr("class")
				if !strings.HasPrefix(cls, "q") {
					return true // keep looking
				}
				wh, _ := span.Attr("data-wowhead")
				if !strings.Contains(wh, "item=") {
					return true
				}
				txt := strings.TrimSpace(span.Text())
				if txt == "" {
					return true
				}
				itemID = extractItemID(wh)
				bonusIDs = extractBonusIDs(wh)
				ilvl = extractIlvl(wh)
				name = txt
				return false // stop
			})

			// Backwards-compatible fallback: take the outer spell_icon_span data-wowhead
			// if no quality-class child was found.
			if itemID == 0 {
				card.Find("span[data-wowhead]").EachWithBreak(func(j int, span *goquery.Selection) bool {
					wh, _ := span.Attr("data-wowhead")
					if !strings.Contains(wh, "item=") {
						return true
					}
					itemID = extractItemID(wh)
					bonusIDs = extractBonusIDs(wh)
					ilvl = extractIlvl(wh)
					name = strings.TrimSpace(span.Text())
					return false
				})
			}

			if itemID == 0 || name == "" {
				return
			}

			// Source label: prefer .bis_item_drop, else any anchor in footer.
			source := strings.TrimSpace(card.Find(".bis_item_drop").First().Text())
			if source == "" {
				source = strings.TrimSpace(card.Find(".bis_item_footer a").First().Text())
			}

			// Handle Ring/Trinket numbering across this section.
			actualSlot := slot
			if slot == "Finger1" {
				fingerCount++
				if fingerCount == 2 {
					actualSlot = "Finger2"
				}
			} else if slot == "Trinket1" {
				trinketCount++
				if trinketCount == 2 {
					actualSlot = "Trinket2"
				}
			}

			items = append(items, GearItem{
				Slot: actualSlot, ItemID: itemID, Name: name, Source: source,
				BonusIDs: bonusIDs, Ilvl: ilvl,
			})
		})
		return items
	}

	// parseLegacyTable parses the old <table> structure inside #sectionID.
	parseLegacyTable := func(sectionID string) []GearItem {
		var items []GearItem
		doc.Find(fmt.Sprintf("#%s table tr", sectionID)).Each(func(i int, tr *goquery.Selection) {
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
				actualSlot := slot
				if j > 0 {
					switch slot {
					case "Finger1":
						actualSlot = "Finger2"
					case "Trinket1":
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

	parseSection := func(sectionID string) []GearItem {
		items := parseBisGrid(sectionID)
		if len(items) == 0 {
			items = parseLegacyTable(sectionID)
		}
		return items
	}

	// Parse known sections by mapping.
	for sectionID, secType := range sectionMapping {
		items := parseSection(sectionID)
		if len(items) == 0 {
			continue
		}
		switch secType {
		case "raid":
			raid = items
		case "mythicplus":
			mythic = items
		case "overall":
			overall = items
		}
	}

	// Fallback when no mapping resolved: try the conventional layouts.
	if len(raid) == 0 && len(mythic) == 0 && len(overall) == 0 {
		overall = parseSection("bis_0_0")
		mythic = parseSection("bis_0_1")
		raid = parseSection("bis_0_2")
	}
	if len(raid) == 0 && len(mythic) == 0 && len(overall) == 0 {
		overall = parseSection("area_1")
		mythic = parseSection("area_2")
		raid = parseSection("area_3")
	}

	// If only overall exists, mirror it into raid/mythic so the addon always has data.
	if len(overall) > 0 {
		if len(raid) == 0 {
			raid = overall
		}
		if len(mythic) == 0 {
			mythic = overall
		}
	}

	// Last-resort scan: any .bis_item cards or any gear table on the page.
	if len(raid) == 0 && len(mythic) == 0 && len(overall) == 0 {
		var scanned []GearItem
		fingerCount := 0
		trinketCount := 0
		doc.Find(".bis_item").Each(func(i int, card *goquery.Selection) {
			slotRaw := strings.TrimSpace(card.Find(".bis_item_slot").First().Text())
			slot := NormalizeSlot(slotRaw)
			if slot == "" {
				return
			}
			var itemID, ilvl int
			var bonusIDs, name string
			card.Find("span[data-wowhead]").EachWithBreak(func(j int, span *goquery.Selection) bool {
				cls, _ := span.Attr("class")
				if !strings.HasPrefix(cls, "q") {
					return true
				}
				wh, _ := span.Attr("data-wowhead")
				if !strings.Contains(wh, "item=") {
					return true
				}
				itemID = extractItemID(wh)
				bonusIDs = extractBonusIDs(wh)
				ilvl = extractIlvl(wh)
				name = strings.TrimSpace(span.Text())
				return false
			})
			if itemID == 0 || name == "" {
				return
			}
			source := strings.TrimSpace(card.Find(".bis_item_drop").First().Text())
			actualSlot := slot
			if slot == "Finger1" {
				fingerCount++
				if fingerCount == 2 {
					actualSlot = "Finger2"
				}
			} else if slot == "Trinket1" {
				trinketCount++
				if trinketCount == 2 {
					actualSlot = "Trinket2"
				}
			}
			scanned = append(scanned, GearItem{Slot: actualSlot, ItemID: itemID, Name: name, Source: source, BonusIDs: bonusIDs, Ilvl: ilvl})
		})
		if len(scanned) > 0 {
			raid = scanned
			mythic = scanned
			overall = scanned
		}
	}

	logf("    Found %d overall, %d raid, %d M+ items\n", len(overall), len(raid), len(mythic))
	return raid, mythic, overall, nil
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
