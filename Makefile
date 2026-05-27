# CE Suite AsciiDoc build
#
# Toolchain requirements:
#   pandoc           -- for 'make adoc' (conversion from Markdown)
#   asciidoctor      -- for 'make html' (gem install asciidoctor rouge)
#   asciidoctor-pdf  -- for 'make pdf'  (gem install asciidoctor-pdf)
#
# Conversion pipeline:
#   docs/chapters/*.md       → docs/adoc/chapters/*.adoc
#   docs/reference/*.md      → docs/adoc/reference/*.adoc
#   docs/submission/*.md     → docs/adoc/submission/*.adoc
#
# Typical workflow:
#   make check   # show which .adoc files are stale or missing
#   make adoc    # regenerate all stale .adoc files
#   make html    # render docs/adoc/index.adoc → build/index.html

PYTHON  := python3
MD2ADOC := tools/md2adoc.py

MD_CHAPTER_SRCS    := $(wildcard docs/chapters/*.md)
MD_REFERENCE_SRCS  := $(wildcard docs/reference/*.md)
MD_SUBMISSION_SRCS := $(wildcard docs/submission/*.md)

ADOC_CHAPTER_TARGETS    := $(patsubst docs/chapters/%.md,docs/adoc/chapters/%.adoc,$(MD_CHAPTER_SRCS))
ADOC_REFERENCE_TARGETS  := $(patsubst docs/reference/%.md,docs/adoc/reference/%.adoc,$(MD_REFERENCE_SRCS))
ADOC_SUBMISSION_TARGETS := $(patsubst docs/submission/%.md,docs/adoc/submission/%.adoc,$(MD_SUBMISSION_SRCS))

ADOC_ALL := $(ADOC_CHAPTER_TARGETS) $(ADOC_REFERENCE_TARGETS) $(ADOC_SUBMISSION_TARGETS)

.PHONY: all adoc html pdf check clean

all: adoc

adoc: $(ADOC_ALL)

docs/adoc/chapters/%.adoc: docs/chapters/%.md
	$(PYTHON) $(MD2ADOC) $< $@

docs/adoc/reference/%.adoc: docs/reference/%.md
	$(PYTHON) $(MD2ADOC) $< $@

docs/adoc/submission/%.adoc: docs/submission/%.md
	$(PYTHON) $(MD2ADOC) $< $@

html: adoc
	@command -v asciidoctor >/dev/null 2>&1 || \
	  { echo "ERROR: asciidoctor not found. Install with: gem install asciidoctor rouge"; exit 1; }
	mkdir -p build
	asciidoctor -D build/ docs/adoc/index.adoc

pdf: adoc
	@command -v asciidoctor-pdf >/dev/null 2>&1 || \
	  { echo "ERROR: asciidoctor-pdf not found. Install with: gem install asciidoctor-pdf"; exit 1; }
	mkdir -p build
	asciidoctor-pdf -D build/ docs/adoc/index.adoc

check:
	@stale=0; \
	for md in $(MD_CHAPTER_SRCS) $(MD_REFERENCE_SRCS) $(MD_SUBMISSION_SRCS); do \
	  adoc=$$(echo "$$md" | sed 's|^docs/|docs/adoc/|; s|\.md$$|.adoc|'); \
	  if [ ! -f "$$adoc" ]; then \
	    echo "MISSING  $$adoc"; stale=1; \
	  elif [ "$$md" -nt "$$adoc" ]; then \
	    echo "STALE    $$adoc"; stale=1; \
	  else \
	    echo "OK       $$adoc"; \
	  fi; \
	done; \
	if [ $$stale -gt 0 ]; then \
	  echo ""; echo "Run 'make adoc' to regenerate stale files."; \
	fi

clean:
	rm -rf build/
