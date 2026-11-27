# 11toon fixtures

Pages saved from https://11toon.com on 2026-11-27 with a desktop Chrome
User-Agent (plain HTTP GET, no login). To keep them small, scripts, styles,
comments, `<link>`/`<meta>` tags and indentation were removed; the markup the
parsers read is untouched. Two scripts were kept: the reader's `img_list` /
`img_list_2` arrays and the "post does not exist" alert.

| File | Request |
| --- | --- |
| `latest_p1.html` | `/bbs/board.php?bo_table=toon_c&type=upd&page=1` |
| `latest_last.html` | `/bbs/board.php?bo_table=toon_c&type=upd&page=491` (last page) |
| `popular_p1.html` | `/bbs/board.php?bo_table=toon_c&is_over=0` |
| `popular_p2.html` | `/bbs/board.php?bo_table=toon_c&is_over=0&page=2` |
| `recommended.html` | `/bbs/board.php?bo_table=toon_c&type=today` |
| `search_onepiece.html` | `/bbs/search_stx.php?stx=원피스` |
| `search_none.html` | `/bbs/search_stx.php?stx=zzqqxxyy` |
| `author_oda.json` | `/bbs/ajax.searchauthor.php?search_key=오다` |
| `author_none.json` | `/bbs/ajax.search.php?search_key=zzqqxxyy` (the author endpoint answers the same) |
| `series_2_p1.html` | `/bbs/board.php?bo_table=toons&is=2` (One Piece, newest 100 of 14 pages) |
| `series_2_p14.html` | `/bbs/board.php?bo_table=toons&is=2&page=14` (oldest page, extras) |
| `series_3737_p1.html` | `...&is=3737` (side stories, specials, .5 chapters) |
| `series_10394.html` | `...&is=10394` (completed, volumes and chapters, titles cut with "…") |
| `series_19.html` | `...&is=19` (volumes, "10.5권", "312화(완)") |
| `series_8158.html` | `...&is=8158` (long series name spelled several ways) |
| `series_34801.html` | `...&is=34801` (bare numbers, "출장판", "특별편") |
| `series_missing.html` | `...&is=99999999` (unknown id, still HTTP 200) |
| `chapter_1834578.html` | `/bbs/board.php?bo_table=toons&wr_id=1834578&is=2` |
| `chapter_missing.html` | `/bbs/board.php?bo_table=toons&wr_id=999999999&is=2` |
