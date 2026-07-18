XCODE_DEVELOPER_DIR ?= $(HOME)/Downloads/Xcode-beta.app/Contents/Developer
CARINA_DERIVED_DATA ?= /tmp/CARINA-DerivedData

.PHONY: dashboard verify archive-dry-run forge forge-status forge-install iphone-live-view device-control-install device-control-start ios-device-build

dashboard:
	python3 src/build_dashboard.py

verify:
	python3 -m py_compile src/build_dashboard.py src/archive_codex_review.py src/token_counter.py
	python3 -m unittest discover -s tests
	python3 src/build_dashboard.py
	python3 src/token_counter.py --text "caRINA token check"

archive-dry-run:
	python3 src/archive_codex_review.py --dry-run

forge:
	python3 scripts/carina_forge.py ingest

forge-status:
	python3 scripts/carina_forge.py status

forge-install:
	./scripts/install_carina_forge_launch_agent.sh

iphone-live-view:
	./scripts/open_iphone_hands_on_view.sh

device-control-install:
	./scripts/install_carina_device_control_launch_agent.sh

device-control-start:
	./scripts/carina_device_control.py start

ios-device-build:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcodebuild \
		-project apps/ios/Carina.xcodeproj \
		-scheme Carina \
		-configuration Debug \
		-destination 'generic/platform=iOS' \
		-derivedDataPath "$(CARINA_DERIVED_DATA)" \
		-allowProvisioningUpdates \
		build
