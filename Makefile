# Goody's Calculator — classic four-function desk calculator (Free Pascal)
#
# macOS:   make
# Linux:   sudo apt install fpc libgtk2.0-dev   &&  make linux
# Windows: from a native FPC install:            make windows

FPC      ?= fpc
SRC      := src
BUILD    := build
APP      := $(BUILD)/GoodysCalculator.app
UNITS    := -Fu$(SRC) -FU$(BUILD) -FE$(BUILD)
FLAGS    := -Mobjfpc -Scgi -O2 -Xs

.PHONY: all app run linux windows test snap clean

all: app

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/GoodysCalculator: $(BUILD) $(SRC)/*.pas
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/GoodysCalculator $(SRC)/calculator.pas

$(BUILD)/calctest: $(BUILD) $(SRC)/ucalcmodel.pas $(SRC)/calctest.pas
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/calctest $(SRC)/calctest.pas

app: $(BUILD)/GoodysCalculator
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BUILD)/GoodysCalculator $(APP)/Contents/MacOS/GoodysCalculator
	cp bundle/Info.plist $(APP)/Contents/Info.plist

run: app
	open $(APP)

linux: $(BUILD)
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/goodyscalculator $(SRC)/calculator.pas

windows: $(BUILD)
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/GoodysCalculator.exe $(SRC)/calculator.pas

test: $(BUILD)/calctest
	$(BUILD)/calctest

$(BUILD)/calcsnap: $(BUILD) $(SRC)/*.pas
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/calcsnap $(SRC)/calcsnap.pas

snap: $(BUILD)/calcsnap
	$(BUILD)/calcsnap $(BUILD)

clean:
	rm -rf $(BUILD)
