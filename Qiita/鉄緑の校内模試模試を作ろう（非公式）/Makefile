EXAM = mock-exam
ANSWER = mock-answersheet
BUILD = build

.PHONY: all render clean

all:
	mkdir -p $(BUILD)
	latexmk -r .latexmkrc -outdir=$(BUILD) $(EXAM).tex
	latexmk -r .latexmkrc -outdir=$(BUILD) $(ANSWER).tex
	cp $(BUILD)/$(EXAM).pdf $(EXAM).pdf
	cp $(BUILD)/$(ANSWER).pdf $(ANSWER).pdf

render: all
	mkdir -p tmp/pdfs/exam tmp/pdfs/answersheet
	pdftoppm -png -r 150 $(EXAM).pdf tmp/pdfs/exam/page
	pdftoppm -png -r 150 $(ANSWER).pdf tmp/pdfs/answersheet/page

clean:
	latexmk -r .latexmkrc -outdir=$(BUILD) -c $(EXAM).tex
	latexmk -r .latexmkrc -outdir=$(BUILD) -c $(ANSWER).tex

