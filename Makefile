XCODE_DEVELOPER_DIR ?= $(HOME)/Downloads/Xcode-beta.app/Contents/Developer
CARINA_DERIVED_DATA ?= /tmp/CARINA-DerivedData

.PHONY: dashboard dashboard-install dashboard-status verify archive-dry-run forge forge-status forge-install deployment-guardian-install deployment-guardian-status deployment-guardian-run iphone-live-view device-control-install device-control-start ios-device-build

dashboard:
	python3 src/build_dashboard.py

dashboard-install:
	./scripts/install_carina_dashboard_launch_agent.sh

dashboard-status:
	/usr/bin/curl -fsS http://127.0.0.1:51003/health

verify:
	python3 -m py_compile src/build_dashboard.py src/archive_codex_review.py src/token_counter.py scripts/carina_forge.py scripts/carina_deployment_guardian.py scripts/carina_dashboard_service.py apps/bridge/forge_store.py
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

deployment-guardian-install:
	./scripts/install_carina_deployment_guardian.sh

deployment-guardian-status:
	python3 scripts/carina_deployment_guardian.py status

deployment-guardian-run:
	python3 scripts/carina_deployment_guardian.py run

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

system-update-log:
	python3 scripts/update_system_log.py
