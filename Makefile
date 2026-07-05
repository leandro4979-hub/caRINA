.PHONY: dashboard verify archive-dry-run

dashboard:
	python3 src/build_dashboard.py

verify:
	python3 -m py_compile src/build_dashboard.py src/archive_codex_review.py
	python3 src/build_dashboard.py

archive-dry-run:
	python3 src/archive_codex_review.py --dry-run

