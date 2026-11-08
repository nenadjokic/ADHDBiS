package scraper

import "regexp"

// ivTooltipRe matches Icy Veins' own tooltip attribute, which replaced the Wowhead one
// on their pages (seen 2026-11-08):
//
//	data-iv-tooltip="wow/item/281239?bonus=12854:14049"
//
// The parsers were written against the older Wowhead form:
//
//	data-wowhead="item=281239&bonus=12854:14049"
var ivTooltipRe = regexp.MustCompile(`data-iv-tooltip="wow/([a-z-]+)/(\d+)(?:\?([^"]*))?"`)

// normalizeIcyVeinsTooltips rewrites every data-iv-tooltip attribute into the
// data-wowhead form, so one set of parsers handles both the old and the new markup.
// Pages that still use data-wowhead are returned unchanged.
func normalizeIcyVeinsTooltips(body []byte) []byte {
	return ivTooltipRe.ReplaceAllFunc(body, func(m []byte) []byte {
		sub := ivTooltipRe.FindSubmatch(m)
		out := []byte(`data-wowhead="`)
		out = append(out, sub[1]...)
		out = append(out, '=')
		out = append(out, sub[2]...)
		if len(sub[3]) > 0 {
			out = append(out, []byte("&amp;")...)
			out = append(out, sub[3]...)
		}
		return append(out, '"')
	})
}
