package scraper

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// Wowhead pages render content client-side using WH.markup.printHtml() with
// a BBCode-like markup language. Items use [item=XXXXX] syntax, tables use
// [tr][td]...[/td][/tr], and talent codes use [copy="Name"]CODE[/copy].
// Item names are stored in WH.Gatherer.addData(3, ...) JSON.

// --- Item name resolution ---

var gathererRegex = regexp.MustCompile(`WH\.Gatherer\.addData\(3,\s*\d+,\s*(\{.*?\})\)`)

type gathererItem struct {
	NameEnus string `json:"name_enus"`
}

// extractItemNames parses WH.Gatherer.addData(3, N, {...}) to build itemID -> name map.
func extractItemNames(body []byte) map[int]string {
	names := map[int]string{}
	bodyStr := string(body)

	matches := gathererRegex.FindAllStringSubmatch(bodyStr, -1)
	for _, m := range matches {
		if len(m) < 2 {
			continue
		}
		// Parse the JSON object: {"249283": {"name_enus": "...", ...}, ...}
		var raw map[string]json.RawMessage
		if err := json.Unmarshal([]byte(m[1]), &raw); err != nil {
			continue
		}
		for idStr, itemJSON := range raw {
			id, err := strconv.Atoi(idStr)
			if err != nil {
				continue
			}
			var item gathererItem
			if err := json.Unmarshal(itemJSON, &item); err != nil {
				continue
			}
			if item.NameEnus != "" {
				names[id] = item.NameEnus
			}
		}
	}
	return names
}

// --- Markup extraction ---

// extractMarkup pulls the BBCode-like markup string from WH.markup.printHtml(...).
// Format: WH.markup.printHtml("MARKUP_CONTENT", "guide-body", {...})
// The markup is the FIRST string argument (a very long string with escaped slashes).
func extractMarkup(body []byte) string {
	bodyStr := string(body)

	// Find the start of the markup.printHtml call
	marker := `WH.markup.printHtml("`
	idx := strings.Index(bodyStr, marker)
	if idx < 0 {
		return ""
	}

	// Extract the first quoted string argument (handling escaped quotes)
	start := idx + len(marker)
	var sb strings.Builder
	i := start
	for i < len(bodyStr) {
		ch := bodyStr[i]
		if ch == '\\' && i+1 < len(bodyStr) {
			next := bodyStr[i+1]
			switch next {
			case '/':
				sb.WriteByte('/')
			case 'r':
				// skip \r
			case 'n':
				sb.WriteByte('\n')
			case '"':
				sb.WriteByte('"')
			case '\\':
				sb.WriteByte('\\')
			default:
				sb.WriteByte(ch)
				sb.WriteByte(next)
			}
			i += 2
		} else if ch == '"' {
			// End of the string
			break
		} else {
			sb.WriteByte(ch)
			i++
		}
	}

	return sb.String()
}

// --- Gear parsing ---

// Matches gear table rows: [tr][td]Slot[/td][td]...[item=XXXXX...]...[/td][td]Source[/td][/tr]
// Wowhead uses [item=XXXXX bonus=YYY ilvl=ZZZ] or [item=XXXXX]
var wowheadItemRegex = regexp.MustCompile(`\[item=(\d+)((?:\s+[^\]]*)?)\]`)
var wowheadBonusRegex = regexp.MustCompile(`bonus=([0-9:]+)`)
var wowheadIlvlRegex = regexp.MustCompile(`ilvl=(\d+)`)

// gearRowRegex matches a table row with 3 columns: slot, item(s), source.
// Wowhead markup mixes single-line and multi-line BBCode formatting, so the
// row regex must tolerate whitespace/newlines between tags and allow td
// attribute lists (e.g. "[td background=c10]"). (?s) lets "." match newlines.
var gearRowRegex = regexp.MustCompile(`(?s)\[tr\]\s*\[td[^\]]*\](.*?)\[/td\]\s*\[td[^\]]*\](.*?)\[/td\]\s*\[td[^\]]*\](.*?)\[/td\]\s*\[/tr\]`)

// trBlockRegex matches each <tr>...</tr> in markup, tolerant of newlines.
var trBlockRegex = regexp.MustCompile(`(?s)\[tr\](.*?)\[/tr\]`)

// tdCellRegex matches each <td>...</td> cell inside a row.
var tdCellRegex = regexp.MustCompile(`(?s)\[td[^\]]*\](.*?)\[/td\]`)

// validGearSlots is the canonical set of gear slot names. We use it to reject
// rows from non-gear tables (e.g. tier rankings whose first column is "1"/"2").
var validGearSlots = map[string]bool{
	"Head": true, "Neck": true, "Shoulders": true, "Back": true,
	"Chest": true, "Wrist": true, "Hands": true, "Waist": true,
	"Legs": true, "Feet": true, "Finger1": true, "Finger2": true,
	"Trinket1": true, "Trinket2": true, "Weapon": true, "OffHand": true,
	"MainHand": true,
}

// ParseWowheadGear parses BiS gear from a Wowhead guide page.
//
// Wowhead guide pages use a BBCode-like markup printed by WH.markup.printHtml.
// Gear tables have variable column counts: most guides use 3 columns
// (Slot | Item | Source) but some healer/melee tables add an extra column for
// the recommended enchant icon, ending up with 4 columns. We tolerate both by
// walking each row cell-by-cell and identifying the slot, gear item, and
// source columns by their content rather than by fixed index.
func ParseWowheadGear(body []byte) (raid []GearItem, mythic []GearItem, err error) {
	markup := extractMarkup(body)
	if markup == "" {
		logf("    Found 0 raid items, 0 M+ items\n")
		return nil, nil, nil
	}

	names := extractItemNames(body)
	fingerCount := 0
	trinketCount := 0

	for _, row := range trBlockRegex.FindAllStringSubmatch(markup, -1) {
		rowBody := row[1]
		cellMatches := tdCellRegex.FindAllStringSubmatch(rowBody, -1)
		if len(cellMatches) < 2 {
			continue
		}
		cells := make([]string, len(cellMatches))
		for i, m := range cellMatches {
			cells[i] = m[1]
		}

		slotRaw := strings.TrimSpace(extractTextFromMarkup(cells[0]))
		if slotRaw == "" || strings.EqualFold(slotRaw, "Slot") {
			continue
		}

		// Find the cell containing the actual gear item. Items are typically
		// wrapped in [color=qN][item=ID bonus=...][/color] or plain [item=ID ...].
		// Enchant-icon columns use [url=item=ID][icon ...][/url] which we must
		// skip — wowheadItemRegex requires "[item=" so url=item= does not match.
		itemCellIdx := -1
		var itemMatches [][]string
		for i := 1; i < len(cells); i++ {
			matches := wowheadItemRegex.FindAllStringSubmatch(cells[i], -1)
			if len(matches) > 0 {
				itemCellIdx = i
				itemMatches = matches
				break
			}
		}
		if itemCellIdx < 0 {
			continue
		}

		// Source column: any later cell, preferring one with link/text content.
		source := ""
		for j := itemCellIdx + 1; j < len(cells); j++ {
			candidate := strings.TrimSpace(extractTextFromMarkup(cells[j]))
			if candidate != "" {
				source = candidate
				break
			}
		}

		slot := NormalizeSlot(slotRaw)
		if !validGearSlots[slot] {
			continue
		}

		// Handle Ring/Trinket numbering
		if strings.EqualFold(slotRaw, "Ring") || strings.EqualFold(slotRaw, "Finger") {
			fingerCount++
			if fingerCount == 1 {
				slot = "Finger1"
			} else {
				slot = "Finger2"
			}
		}
		if strings.EqualFold(slotRaw, "Trinket") {
			trinketCount++
			if trinketCount == 1 {
				slot = "Trinket1"
			} else {
				slot = "Trinket2"
			}
		}

		for _, im := range itemMatches {
			itemID, _ := strconv.Atoi(im[1])
			if itemID == 0 {
				continue
			}
			name := names[itemID]
			if name == "" {
				name = fmt.Sprintf("Item %d", itemID)
			}

			extra := im[2]
			bonusIDs := ""
			ilvl := 0
			if bm := wowheadBonusRegex.FindStringSubmatch(extra); len(bm) >= 2 {
				bonusIDs = bm[1]
			}
			if ilm := wowheadIlvlRegex.FindStringSubmatch(extra); len(ilm) >= 2 {
				ilvl, _ = strconv.Atoi(ilm[1])
			}

			raid = append(raid, GearItem{
				Slot:     slot,
				ItemID:   itemID,
				Name:     name,
				Source:   source,
				BonusIDs: bonusIDs,
				Ilvl:     ilvl,
			})
		}
	}

	// For Wowhead, use same list for both raid and M+ unless we find separate tabs.
	mythic = make([]GearItem, len(raid))
	copy(mythic, raid)

	logf("    Found %d raid items, %d M+ items\n", len(raid), len(mythic))
	return raid, mythic, nil
}

// --- Enchants/Gems/Consumables parsing ---

// enchantRowRegex matches enchant table rows: [tr][td]Slot[/td][td align=center][item=XXX][/td][/tr]
// Note: some Wowhead rows have extra ] between [/td] and [/tr], and some
// guides format rows across multiple lines with whitespace between tags.
var enchantRowRegex = regexp.MustCompile(`(?s)\[tr\]\s*\[td[^\]]*\](.*?)\[/td\]\s*\[td[^\]]*\](.*?)\[/td\]\]?\s*\[/tr\]`)

// gemListRegex matches gems in list items: [li][b]Type[/b]: [item=XXX][/li]
var gemListRegex = regexp.MustCompile(`\[li\]\[b\]([^[]*)\[/b\]:\s*\[item=(\d+)[^\]]*\]\[/li\]`)

// consumableRowRegex matches consumable table rows.
// Tolerates whitespace between BBCode tags so multi-line markup also matches.
var consumableRowRegex = regexp.MustCompile(`(?s)\[tr\]\s*\[td[^\]]*\](.*?)\[/td\]\s*\[td[^\]]*\]\s*\[item=(\d+)[^\]]*\](?:.*?\[item=(\d+)[^\]]*\])?\s*\[/td\]\s*\[/tr\]`)

// ParseWowheadEnchants parses enchants, gems, and consumables from a Wowhead guide page.
func ParseWowheadEnchants(body []byte) (enchants []EnchantItem, gems []GemItem, consumables []Consumable, err error) {
	markup := extractMarkup(body)
	if markup == "" {
		logf("    Found 0 enchants, 0 gems, 0 consumables\n")
		return nil, nil, nil, nil
	}

	names := extractItemNames(body)

	// Split markup into zones: enchant+gem zone vs consumable zone
	// by finding the [h2...Consumable...] boundary
	enchantZone := markup
	consumableZone := ""

	consumableIdx := -1
	for _, marker := range []string{"[h2", "[h3"} {
		idx := 0
		for {
			pos := strings.Index(markup[idx:], marker)
			if pos < 0 {
				break
			}
			absPos := idx + pos
			// Check if heading text mentions consumable
			headingEnd := strings.Index(markup[absPos:], "]")
			if headingEnd > 0 {
				headingText := strings.ToLower(markup[absPos : absPos+headingEnd])
				if strings.Contains(headingText, "consumable") || strings.Contains(headingText, "cheat sheet") {
					if consumableIdx < 0 || absPos < consumableIdx {
						consumableIdx = absPos
					}
					break
				}
			}
			idx = absPos + len(marker)
		}
	}
	if consumableIdx > 0 {
		enchantZone = markup[:consumableIdx]
		consumableZone = markup[consumableIdx:]
	}

	// Enchant slots to recognize
	enchantSlots := map[string]bool{
		"weapon": true, "helm": true, "head": true, "chest": true,
		"shoulders": true, "legs": true, "boots": true, "feet": true,
		"ring": true, "rings": true, "wrist": true, "back": true, "cloak": true,
	}

	// Parse enchant rows from enchant zone only
	rows := enchantRowRegex.FindAllStringSubmatch(enchantZone, -1)
	for _, row := range rows {
		slotRaw := strings.TrimSpace(row[1])
		slotLower := strings.ToLower(slotRaw)
		itemCell := row[2]

		// Skip header rows
		if slotLower == "slot" || slotLower == "type" {
			continue
		}

		// Diamond and Other Gems go to gems, not enchants
		if slotLower == "diamond" || slotLower == "other gems" {
			itemMatches := wowheadItemRegex.FindAllStringSubmatch(itemCell, -1)
			for _, im := range itemMatches {
				itemID, _ := strconv.Atoi(im[1])
				if itemID == 0 {
					continue
				}
				name := names[itemID]
				if name == "" {
					name = fmt.Sprintf("Item %d", itemID)
				}
				note := ""
				if slotLower == "diamond" {
					note = "unique-equipped"
				}
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
			}
			continue
		}

		// Skip non-enchant slots
		if !enchantSlots[slotLower] {
			continue
		}

		slot := NormalizeSlot(slotRaw)
		itemMatches := wowheadItemRegex.FindAllStringSubmatch(itemCell, 1) // take first item only
		for _, im := range itemMatches {
			itemID, _ := strconv.Atoi(im[1])
			if itemID == 0 {
				continue
			}
			name := names[itemID]
			if name == "" {
				name = fmt.Sprintf("Item %d", itemID)
			}
			enchants = append(enchants, EnchantItem{Slot: slot, ItemID: itemID, Name: name})
		}
	}

	// Also parse gems from list format: [li][b]Type[/b]: [item=XXX][/li]
	gemMatches := gemListRegex.FindAllStringSubmatch(enchantZone, -1)
	for _, gm := range gemMatches {
		itemID, _ := strconv.Atoi(gm[2])
		if itemID == 0 {
			continue
		}
		name := names[itemID]
		if name == "" {
			name = fmt.Sprintf("Item %d", itemID)
		}
		note := ""
		if strings.EqualFold(gm[1], "Diamond") {
			note = "unique-equipped"
		}
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
	}

	// Parse consumables from the consumable zone table
	if consumableZone != "" {
		consRows := consumableRowRegex.FindAllStringSubmatch(consumableZone, -1)
		for _, cr := range consRows {
			typeRaw := strings.TrimSpace(cr[1])
			cType := normalizeConsumableType(typeRaw)
			if cType == "" {
				continue
			}

			// First item
			itemID, _ := strconv.Atoi(cr[2])
			if itemID > 0 {
				name := names[itemID]
				if name == "" {
					name = fmt.Sprintf("Item %d", itemID)
				}
				consumables = append(consumables, Consumable{Type: cType, ItemID: itemID, Name: name})
			}

			// Second item (e.g., Food row with feast + personal food)
			if cr[3] != "" {
				itemID2, _ := strconv.Atoi(cr[3])
				if itemID2 > 0 {
					name := names[itemID2]
					if name == "" {
						name = fmt.Sprintf("Item %d", itemID2)
					}
					consumables = append(consumables, Consumable{Type: cType, ItemID: itemID2, Name: name})
				}
			}
		}
	}

	// Fallback: if no consumables from table, try section-based parsing
	if len(consumables) == 0 {
		zone := consumableZone
		if zone == "" {
			zone = markup
		}
		consumables = parseConsumablesFromSections(zone, names)
	}

	logf("    Found %d enchants, %d gems, %d consumables\n", len(enchants), len(gems), len(consumables))
	return enchants, gems, consumables, nil
}

func normalizeConsumableType(raw string) string {
	lower := strings.ToLower(raw)
	switch {
	case strings.Contains(lower, "flask"):
		return "Flask"
	case strings.Contains(lower, "combat potion"):
		return "Potion"
	case strings.Contains(lower, "potion"):
		return "Potion"
	case strings.Contains(lower, "food"):
		return "Food"
	case strings.Contains(lower, "weapon"):
		return "Weapon Rune"
	case strings.Contains(lower, "augment"):
		return "Rune"
	case strings.Contains(lower, "health"):
		return "Potion"
	}
	return ""
}

// parseConsumablesFromSections extracts consumables from h3 sections
func parseConsumablesFromSections(markup string, names map[int]string) []Consumable {
	var consumables []Consumable

	// Split by [h3 ...] headings
	sectionRegex := regexp.MustCompile(`\[h3[^\]]*\]([^[]*)\[/h3\]`)
	sections := sectionRegex.FindAllStringSubmatchIndex(markup, -1)

	for i, section := range sections {
		heading := markup[section[2]:section[3]]
		headingLower := strings.ToLower(heading)

		cType := ""
		switch {
		case strings.Contains(headingLower, "flask"):
			cType = "Flask"
		case strings.Contains(headingLower, "combat potion"):
			cType = "Potion"
		case strings.Contains(headingLower, "health potion"):
			cType = "Potion"
		case strings.Contains(headingLower, "weapon"):
			cType = "Weapon Rune"
		case strings.Contains(headingLower, "augment"):
			cType = "Rune"
		case strings.Contains(headingLower, "food"):
			cType = "Food"
		default:
			continue
		}

		// Get content between this heading and the next
		start := section[1]
		end := len(markup)
		if i+1 < len(sections) {
			end = sections[i+1][0]
		}
		content := markup[start:end]

		// Extract items from this section
		itemMatches := wowheadItemRegex.FindAllStringSubmatch(content, -1)
		for _, im := range itemMatches {
			itemID, _ := strconv.Atoi(im[1])
			if itemID == 0 {
				continue
			}
			name := names[itemID]
			if name == "" {
				name = fmt.Sprintf("Item %d", itemID)
			}
			// Avoid duplicates
			isDupe := false
			for _, c := range consumables {
				if c.ItemID == itemID {
					isDupe = true
					break
				}
			}
			if !isDupe {
				consumables = append(consumables, Consumable{Type: cType, ItemID: itemID, Name: name})
			}
		}
	}
	return consumables
}

// --- Talent parsing ---

// copyTagRegex matches [copy="Name"]CODE[/copy] (after unescape, quotes are plain)
var copyTagRegex = regexp.MustCompile(`\[copy="([^"]*)"\]([A-Za-z0-9+/=_-]+)`)

// ParseWowheadTalents parses talent builds from a Wowhead talents guide page.
func ParseWowheadTalents(body []byte) (builds []TalentBuild, err error) {
	markup := extractMarkup(body)

	// Try parsing from markup first
	if markup != "" {
		matches := copyTagRegex.FindAllStringSubmatch(markup, -1)
		for _, m := range matches {
			name := strings.TrimSpace(m[1])
			code := strings.TrimSpace(m[2])
			if code == "" {
				continue
			}

			context := guessTalentContext(name)

			// Avoid duplicate codes
			isDupe := false
			for _, b := range builds {
				if b.Code == code {
					isDupe = true
					break
				}
			}
			if !isDupe {
				builds = append(builds, TalentBuild{Name: name, Code: code, Context: context})
			}
		}
	}

	// Fallback: search raw body for copy patterns (the markup may be unescaped differently)
	if len(builds) == 0 {
		bodyStr := string(body)
		// Try unescaped variant
		altRegex := regexp.MustCompile(`\[copy="([^"]*)"\]([A-Za-z0-9+/=_-]{30,})`)
		matches := altRegex.FindAllStringSubmatch(bodyStr, -1)
		for _, m := range matches {
			name := strings.TrimSpace(m[1])
			code := strings.TrimSpace(m[2])
			context := guessTalentContext(name)

			isDupe := false
			for _, b := range builds {
				if b.Code == code {
					isDupe = true
					break
				}
			}
			if !isDupe {
				builds = append(builds, TalentBuild{Name: name, Code: code, Context: context})
			}
		}
	}

	logf("    Found %d talent builds\n", len(builds))
	return builds, nil
}

func guessTalentContext(name string) string {
	lower := strings.ToLower(name)
	switch {
	case strings.Contains(lower, "mythic") || strings.Contains(lower, "m+") ||
		strings.Contains(lower, "dungeon") || strings.Contains(lower, "aoe"):
		return "mythicplus"
	case strings.Contains(lower, "delve"):
		return "delves"
	case strings.Contains(lower, "pvp"):
		return "pvp"
	case strings.Contains(lower, "raid") || strings.Contains(lower, "single") ||
		strings.Contains(lower, "boss") || strings.Contains(lower, "st"):
		return "raid"
	default:
		return "general"
	}
}

// --- Utility ---

// extractTextFromMarkup strips BBCode tags to get plain text.
// e.g., [url guide=33233]Belo'ren[/url] -> Belo'ren
var bbcodeTagRegex = regexp.MustCompile(`\[[^\]]*\]`)

func extractTextFromMarkup(s string) string {
	result := bbcodeTagRegex.ReplaceAllString(s, "")
	return strings.TrimSpace(result)
}
