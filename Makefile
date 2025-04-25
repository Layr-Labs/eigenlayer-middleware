storage-report:
	bash ".github/bin/storage-report.sh" "docs/storage-report/"

compile:
	forge build

bindings: compile
	./bin/generate-bindings.sh