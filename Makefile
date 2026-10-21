.PHONY: dashboard verify archive-dry-run browser-test

dashboard:
	python3 src/build_dashboard.py

browser-test:
	npm run test:browser

verify:
	npx markdownlint-cli2 "**/*.md" "#node_modules" "#.venv"
	python3 -m py_compile src/build_dashboard.py src/archive_codex_review.py src/token_counter.py src/file_workflow.py
	python3 -m unittest discover -s tests
	npm run test:browser
	python3 src/build_dashboard.py
	python3 src/token_counter.py --text "caRINA token check"

archive-dry-run:
	python3 src/archive_codex_review.py --dry-run
