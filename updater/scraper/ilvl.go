package scraper

import (
	"encoding/json"
	"fmt"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// wowheadTooltipResponse represents the JSON returned by the Wowhead tooltip API.
type wowheadTooltipResponse struct {
	Tooltip string `json:"tooltip"`
	Name    string `json:"name"`
	Quality int    `json:"quality"`
}

var (
	wowheadIlvlCommentRegex = regexp.MustCompile(`<!--ilvl-->(\d+)`)
	htmlTagRegex             = regexp.MustCompile(`<[^>]+>`)
	htmlCommentRegex         = regexp.MustCompile(`<!--[^>]*-->`)
	multiSpaceRegex          = regexp.MustCompile(`\s{2,}`)
	htmlEntityMap            = map[string]string{
		"&amp;":  "&",
		"&lt;":   "<",
		"&gt;":   ">",
		"&quot;": "\"",
		"&#39;":  "'",
		"&nbsp;": " ",
	}
)

// fetchWowheadTooltip fetches the raw tooltip JSON from Wowhead.
func fetchWowheadTooltip(itemID int, bonusIDs string) (*wowheadTooltipResponse, error) {
	url := fmt.Sprintf("https://nether.wowhead.com/tooltip/item/%d?bonus=%s&dataEnv=1&locale=0", itemID, bonusIDs)

	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", userAgent)

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	var tooltipResp wowheadTooltipResponse
	if err := json.NewDecoder(resp.Body).Decode(&tooltipResp); err != nil {
		return nil, err
	}
	return &tooltipResp, nil
}

// decodeHTMLEntities replaces common HTML entities with their characters.
func decodeHTMLEntities(s string) string {
	for entity, char := range htmlEntityMap {
		s = strings.ReplaceAll(s, entity, char)
	}
	return s
}

// ParseWowheadTooltip converts Wowhead tooltip HTML into clean text lines for display.
// Returns the lines and the extracted ilvl.
func ParseWowheadTooltip(html string) ([]string, int) {
	if html == "" {
		return nil, 0
	}

	// Extract ilvl before stripping
	ilvl := 0
	if m := wowheadIlvlCommentRegex.FindStringSubmatch(html); len(m) >= 2 {
		ilvl, _ = strconv.Atoi(m[1])
	}

	// Remove sell price div and everything after (not useful for BiS display)
	if idx := strings.Index(html, `<div class="whtt-sellprice"`); idx >= 0 {
		html = html[:idx]
	}

	// Remove "Requires Level" line (not useful)
	reqLevelRe := regexp.MustCompile(`Requires Level\s*<!--rlvl-->\d+`)
	html = reqLevelRe.ReplaceAllString(html, "")

	// Strip HTML comments (they contain internal markers)
	html = htmlCommentRegex.ReplaceAllString(html, "")

	// Replace <br> and </td></tr></table> boundaries with newlines
	html = strings.ReplaceAll(html, "<br>", "\n")
	html = strings.ReplaceAll(html, "<br/>", "\n")
	html = strings.ReplaceAll(html, "<br />", "\n")
	html = strings.ReplaceAll(html, "</table>", "\n")
	html = strings.ReplaceAll(html, "</tr>", "\n")

	// Handle td/th as tab separators (for slot/type and damage/speed rows)
	html = strings.ReplaceAll(html, "</td><th>", "\t")
	html = strings.ReplaceAll(html, "</td><th ", "\t<th ")

	// Strip remaining HTML tags
	html = htmlTagRegex.ReplaceAllString(html, "")

	// Decode HTML entities
	html = decodeHTMLEntities(html)

	// Split into lines and clean up
	var lines []string
	for _, raw := range strings.Split(html, "\n") {
		line := strings.TrimSpace(raw)
		// Replace tab separators with padding for alignment
		if strings.Contains(line, "\t") {
			parts := strings.SplitN(line, "\t", 2)
			left := strings.TrimSpace(parts[0])
			right := strings.TrimSpace(parts[1])
			if left != "" || right != "" {
				line = left + "  |  " + right
			}
		}
		// Collapse multiple spaces
		line = multiSpaceRegex.ReplaceAllString(line, " ")
		if line == "" {
			continue
		}
		lines = append(lines, line)
	}

	return lines, ilvl
}

// FetchWowheadIlvl fetches the effective item level from Wowhead's tooltip API.
func FetchWowheadIlvl(itemID int, bonusIDs string) int {
	resp, err := fetchWowheadTooltip(itemID, bonusIDs)
	if err != nil {
		return 0
	}
	if m := wowheadIlvlCommentRegex.FindStringSubmatch(resp.Tooltip); len(m) >= 2 {
		ilvl, _ := strconv.Atoi(m[1])
		return ilvl
	}
	return 0
}

// FetchWowheadTooltipLines fetches and parses tooltip lines + ilvl from Wowhead.
func FetchWowheadTooltipLines(itemID int, bonusIDs string) ([]string, int) {
	resp, err := fetchWowheadTooltip(itemID, bonusIDs)
	if err != nil {
		return nil, 0
	}
	return ParseWowheadTooltip(resp.Tooltip)
}

// ResolveGearIlvl fills in missing ilvl and tooltip data for gear items using the Wowhead tooltip API.
func ResolveGearIlvl(items []GearItem) {
	for i := range items {
		if items[i].BonusIDs == "" {
			continue
		}
		lines, ilvl := FetchWowheadTooltipLines(items[i].ItemID, items[i].BonusIDs)
		if ilvl > 0 {
			items[i].Ilvl = ilvl
		}
		if len(lines) > 0 {
			items[i].TooltipLines = lines
		}
		logf("    Resolved %s (item %d): ilvl %d, %d tooltip lines\n",
			items[i].Name, items[i].ItemID, ilvl, len(lines))
		// Small delay to be polite to Wowhead
		time.Sleep(200 * time.Millisecond)
	}
}
