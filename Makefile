INSTALL_PATH = /usr/local/bin/uc-string-obfuscator

build:
	swift package update
	swift build -c release

install: build
	sudo cp -f .build/release/uc-string-obfuscator $(INSTALL_PATH)

clean:
	rm -rf .build

uninstall:
	rm -f $(INSTALL_PATH)

xcode:
	swift package generate-xcodeproj
	xed .
