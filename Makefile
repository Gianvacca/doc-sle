#
# Copyright (c) 2014 Rick Salevsky <rsalevsky@suse.de>
# Copyright (c) 2016 Stefan Knorr <sknorr@suse.de>
# Copyright (c) 2018 Alessio Adamo <alessio@alessioadamo.com>
#

# How to use this makefile:
# * After updating the XML: $ make po
# * When creating output:   $ make linguas; make all
# * To clean up:            $ make clean

.PHONY: clean_po_temp clean_mo clean_pot clean linguas po pot translate validate pdf text single-html translatedxml

ifndef BOOKS_TO_TRANSLATE
# Set default books to be translated
  BOOKS_TO_TRANSLATE := DC-SLED-all DC-SLES-all DC-opensuse-all
endif
ifndef LANGS
# Set translation languages. TO DO: rework the po-selector script 
  LANGS := $(shell cat LINGUAS)
endif
  LANGSEN := $(LANGS) en
ifndef STYLEROOT
  STYLEROOT := /usr/share/xml/docbook/stylesheet/opensuse2013-ns
endif
ifndef VERSION
  VERSION := unreleased
endif
ifndef DATE
  DATE := $(shell date +%Y-%0m-%0d)
endif

# Allows for DocBook profiling (hiding/showing some text).
LIFECYCLE_VALID := beta pre maintained unmaintained
ifndef LIFECYCLE
  LIFECYCLE := maintained
endif
ifneq "$(LIFECYCLE)" "$(filter $(LIFECYCLE),$(LIFECYCLE_VALID))"
  override LIFECYCLE := maintained
endif

# The list of available languages is retrieved by searching for subdirs with
# pattern lang/po and removing the '/po' suffix
LANG_LIST := $(subst /po,,$(wildcard */po))

# The list of source files is represented by all '.xml' files in xml/ dir
# except schemas.xml which does not contain translatable strings
XML_LIST := $(filter-out xml/schemas.xml,$(wildcard xml/*.xml))

# The list of entities is represented by all '.ent' files in xml/ dir
# plus entities.abbrev
ENT_FILES := $(wildcard xml/*.ent)
ENT_FILES += xml/entities.abbrev

# The PO domain list is generated by taking the basename of the source files
# and removing the dir part
DOMAIN_LIST := $(basename $(notdir $(XML_LIST)))

# The list of POT files is generated by attaching the '50-pot/' prefix and the
# '.pot' suffix to each domain
POT_FILES := $(foreach DOMAIN,$(DOMAIN_LIST),50-pot/$(DOMAIN).pot)

# The list of PO files is generated as follows. First, for each available language
# it is generated a pattern like 'lang/po/_DOMAIN_NAME_.lang.po', then the placeholder
# _DOMAIN_NAME_ is substituted with each available domain to get a pattern like
# 'lang/po/domain.lang.po'
PO_FILES := $(foreach DOMAIN,$(DOMAIN_LIST),$(subst _DOMAIN_NAME_,$(DOMAIN),$(foreach LANG,$(LANG_LIST),$(LANG)/po/_DOMAIN_NAME_.$(LANG).po)))

SELECTED_XML_FILES := $(shell cat XML_SOURCES_PER_DC)

# If LANGS is not defined, for output, use only those files that have at least 60% translations
MO_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/po/,$(addsuffix .$(LANG).mo,$(shell cat XML_SOURCES_PER_DC | sed 's@xml/@@; s@\.xml@@' ))))
XML_DEST_FILES := $(foreach LANG, $(LANGS), $(addprefix $(LANG)/,$(SELECTED_XML_FILES)))
ENT_DEST_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/,$(ENT_FILES)))
SCHEMAS_XML_DEST_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/xml/,schemas.xml))
DC_DEST_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/,$(BOOKS_TO_TRANSLATE)))
# PDF_FILES := $(foreach l, $(LANGSEN), build/release-notes.$(l)/release-notes.$(l)_color_$(l).pdf)
# SINGLE_HTML_FILES := $(foreach l, $(LANGSEN), build/release-notes.$(l)/single-html/release-notes.$(l)/index.html)
# TXT_FILES := $(foreach l, $(LANGSEN), build/release-notes.$(l)/release-notes.$(l).txt)

# Gets the language code: release-notes.en.xml => en
DAPS_COMMAND_BASIC = daps -vv  
DAPS_COMMAND = $(DAPS_COMMAND_BASIC) -d 

# Gets the xml source starting from target POT, or xml destination
XML_SOURCE = $(addprefix xml/,$(addsuffix .xml,$(basename $(@F))))
# Gets the po template starting from target PO
PO_TEMPLATE = $(addprefix 50-pot/,$(addsuffix .pot,$(basename $(basename $(@F)))))
# Gets the input po starting from target MO
PO_FILE = $(addsuffix .po,$(basename $@))
# Gets the input mo starting from xml destination
MO_FILE = $(addprefix $(subst xml,po,$(@D)/),$(addsuffix .mo,$(addsuffix .$(subst /xml,,$(@D)),$(basename $(@F)))))
# Turns a space-separated prereq list into a comma-separated list
COMMA := ,
EMPTY :=
SPACE := $(EMPTY) $(EMPTY)
PREREQ_LIST_COMMA_SEPARATED = $(subst $(SPACE),$(COMMA),$^)

ITSTOOL = itstool -i /usr/share/itstool/its/docbook5.its

XSLTPROC_COMMAND = xsltproc \
--stringparam generate.toc "book toc" \
--stringparam generate.section.toc.level 0 \
--stringparam section.autolabel 1 \
--stringparam section.label.includes.component.label 2 \
--stringparam variablelist.as.blocks 1 \
--stringparam toc.max.depth 3 \
--stringparam show.comments 0 \
--xinclude --nonet

# Fetch correct Report Bug link values, so translations get the correct
# version
XPATHPREFIX := //*[local-name()='docmanager']/*[local-name()='bugtracker']/*[local-name()
URL = `xmllint --noent --xpath "$(XPATHPREFIX)='url']/text()" xml/release-notes.xml`
PRODUCT = `xmllint --noent --xpath "$(XPATHPREFIX)='product']/text()" xml/release-notes.xml`
COMPONENT = `xmllint --noent --xpath "$(XPATHPREFIX)='component']/text()" xml/release-notes.xml`
ASSIGNEE = `xmllint --noent --xpath "$(XPATHPREFIX)='assignee']/text()" xml/release-notes.xml`


all: single-html pdf text

linguas: LINGUAS
LINGUAS: $(PO_FILES) 50-tools/po-selector
	50-tools/po-selector

XML_SOURCES_PER_DC:
	@echo "Finding XML sources of books selected for translation..."; \
	for DC_FILE in $(BOOKS_TO_TRANSLATE); do \
	for SOURCE_FILE in $$(daps -d $$DC_FILE list-srcfiles); do \
	echo $$SOURCE_FILE | grep -v '.ent' | grep -q '/xml/'; \
	if [ $${PIPESTATUS[2]} -eq "0" ]; \
	then echo "xml/$$(basename $$SOURCE_FILE)"; \
	fi; \
	done; \
	done | sort | uniq > XML_SOURCES_PER_DC

pot: $(POT_FILES)
50-pot/%.pot: xml/*.xml
	$(ITSTOOL) -o $@ $<

po: $(PO_FILES)

define update_po
$(1)/%.po: 50-pot/%.pot
	if [ -r $$@ ]; then \
	msgmerge  --previous --update $$@ $$<; \
	else \
	msgen -o $$@ $$<; \
	fi
endef   

$(foreach LANG, $(LANG_LIST), $(eval $(call update_po, $(LANG)/po)))

mo: $(MO_FILES)
%.mo: %.po
	msgfmt $< -o $@

# FIXME: Enable use of its:translate attribute in GeekoDoc/DocBook...
translate: $(XML_DEST_FILES) $(SCHEMAS_XML_DEST_FILES) $(ENT_DEST_FILES) $(DC_DEST_FILES)
$(XML_DEST_FILES): $(MO_FILES) $(XML_SOURCE_FILES)
	if [ ! -d $(@D) ]; then mkdir -p $(@D); fi
	$(ITSTOOL) -m $(MO_FILE) -o $(@D) $(XML_SOURCE)
#	sed -i -r \
#	  -e 's_\t+_ _' -e 's_\s+$$__' \
#	  $@.0
#	xsltproc \
#	  --stringparam 'version' "$(VERSION)" \
#	  --stringparam 'dmurl' "$(URL)" \
#	  --stringparam 'dmproduct' "$(PRODUCT)" \
#	  --stringparam 'dmcomponent' "$(COMPONENT)" \
#	  --stringparam 'dmassignee' "$(ASSIGNEE)" \
#	  --stringparam 'date' "$(DATE)" \
#	  fix-up.xsl $@.0 \
#	  > $@
#	rm $@.0
	daps-xmlformat -i $@
#	$(DAPS_COMMAND_BASIC) -m $@ validate

$(SCHEMAS_XML_DEST_FILES): xml/schemas.xml
	ln -sf ../../$^ $(@D)
	
$(ENT_DEST_FILES): $(ENT_FILES)
	for ENT_FILE in $^; do \
	ln -sf ../../$$ENT_FILE $(@D); \
	done;

$(DC_DEST_FILES): $(DC_SOURCE_FILES)
	cp $(@F) $(@D)

validate: $(DC_DEST_FILES)
	for DC_FILE in $^; do \
	$(DAPS_COMMAND) $$DC_FILE validate; \
	done; 

translatedxml: xml/release-notes.xml xml/release-notes.ent $(XML_FILES)
	xsltproc \
	  --stringparam 'version' "$(VERSION)" \
	  --stringparam 'dmurl' "$(URL)" \
	  --stringparam 'dmproduct' "$(PRODUCT)" \
	  --stringparam 'dmcomponent' "$(COMPONENT)" \
	  --stringparam 'dmassignee' "$(ASSIGNEE)" \
	  --stringparam 'date' "$(DATE)" \
	  fix-up.xsl $< \
	  > xml/release-notes.en.xml

pdf: $(PDF_FILES)
$(PDF_FILES): LINGUAS translatedxml
	lang=$(LANG_COMMAND) ; \
	$(DAPS_COMMAND) pdf PROFCONDITION="general\;$(LIFECYCLE)"

single-html: $(SINGLE_HTML_FILES)
$(SINGLE_HTML_FILES): LINGUAS translatedxml
	lang=$(LANG_COMMAND) ; \
	$(DAPS_COMMAND) html --single \
	--stringparam "homepage='https://www.opensuse.org'" \
	PROFCONDITION="general\;$(LIFECYCLE)"

text: $(TXT_FILES)
$(TXT_FILES): LINGUAS translatedxml
	lang=$(LANG_COMMAND) ; \
	LANG=$${lang} $(DAPS_COMMAND) text \
	PROFCONDITION="general\;$(LIFECYCLE)"

clean_po_temp:
	rm -rf $(foreach LANG,$(LANG_LIST),$(addprefix $(LANG),/po/~*))
	
clean_mo:
	rm -rf $(MO_FILES)

clean_pot:
	rm -rf $(POT_FILES)
	
clean: clean_po_temp clean_mo clean_pot
	rm -rf LINGUAS XML_SOURCES_PER_DC $(foreach LANG,$(LANG_LIST),$(addprefix $(LANG),/xml/)) build/
