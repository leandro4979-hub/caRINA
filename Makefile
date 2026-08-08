.PHONY: dashboard verify archive-dry-run

dashboard:
	python3 src/build_dashboard.py

verify:
	npx markdownlint-cli2 "**/*.md" "#node_modules"
	python3 -m py_compile src/build_dashboard.py src/archive_codex_review.py src/token_counter.py
	python3 -m unittest discover -s tests
	python3 src/build_dashboard.py
	python3 src/token_counter.py --text "caRINA token check"

archive-dry-run:
	python3 src/archive_codex_review.py --dry-run
