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

# The list of available languages is retrieved by searching for subdirs with
# pattern lang/po and removing the '/po' suffix
FULL_LANG_LIST := $(subst /po,,$(wildcard */po))

# The list of available books is retrieved by searching for pattern DC-*
FULL_BOOK_LIST := $(wildcard DC-*)

# The list of source files is represented by all '.xml' files in xml/ dir
# except schemas.xml which does not contain translatable strings
FULL_XML_LIST := $(filter-out xml/schemas.xml,$(wildcard xml/*.xml))

# The list of entities is represented by all '.ent' files in xml/ dir
FULL_ENT_LIST := $(wildcard xml/*.ent)

FULL_IMAGE_LIST := $(wildcard images/src/*/*)

# The PO domain list is generated by taking the basename of the source files
# and removing the dir part
FULL_DOMAIN_LIST := $(basename $(notdir $(FULL_XML_LIST)))

# The list of POT files is generated by attaching the '50-pot/' prefix and the
# '.pot' suffix to each domain
FULL_POT_LIST := $(foreach DOMAIN,$(FULL_DOMAIN_LIST),50-pot/$(DOMAIN).pot)

# The list of PO files is generated as follows. First, for each available language
# it is generated a pattern like 'lang/po/_DOMAIN_NAME_.lang.po', then the placeholder
# _DOMAIN_NAME_ is substituted with each available domain to get a pattern like
# 'lang/po/domain.lang.po'
FULL_PO_LIST := $(foreach DOMAIN,$(FULL_DOMAIN_LIST),$(subst _DOMAIN_NAME_,$(DOMAIN),$(foreach LANG,$(FULL_LANG_LIST),$(LANG)/po/_DOMAIN_NAME_.$(LANG).po)))

# The list of MO files is generated by substituting the extension .po with .mo in
# FULL_PO_LIST
FULL_MO_LIST := $(patsubst %.po,%.mo,$(FULL_PO_LIST))

# If not specified, the default books to be translated are DC-SLED-all, DC-SLES-all,
# DC-opensuse-all
ifndef BOOKS_TO_TRANSLATE
  BOOKS_TO_TRANSLATE := DC-SLED-all DC-SLES-all DC-opensuse-all
endif

# The variable 'SELECTED_SOURCES" is necessary only for targets that are related to the translation of
# the XMLs. It relies on the 'xml-selector' script which in turn relies on the command 'daps list-srcfiles'.
# Since this operation is time consuming, it is performed # only for a subset of targets (specifically 'mo', 
# 'translate', 'validate', 'pdf', 'single-html', 'text'). See variable 'CHECK_IF_TO_BE_TRANSLATED'.
CHECK_IF_TO_BE_TRANSLATED := $(or $(filter mo,$(MAKECMDGOALS)),$(filter translate,$(MAKECMDGOALS)),$(filter validate,$(MAKECMDGOALS)),$(filter pdf,$(MAKECMDGOALS)),$(filter single-html,$(MAKECMDGOALS)),$(filter text,$(MAKECMDGOALS)))
ifdef CHECK_IF_TO_BE_TRANSLATED
  # Determine the sources necessary to build selected books
  SELECTED_SOURCES := $(shell 50-tools/xml-selector $(BOOKS_TO_TRANSLATE) | tee /dev/tty | sed '1d; s@XML sources of .*: @@; /^$$/d' | tr ' ' '\n' | sort -u)
endif

# These are the xml files required for the selected books stored in the
# variable "BOOKS_TO_TRANSLATE"
SELECTED_XML_FILES := $(filter %.xml,$(SELECTED_SOURCES))

# These are the ent files required for the selected books stored in the
# variable "BOOKS_TO_TRANSLATE"
SELECTED_ENT_FILES := $(filter %.ent,$(SELECTED_SOURCES))

# These are the PO domain list required for the translation of selected books stored in the
# variable "BOOKS_TO_TRANSLATE"
SELECTED_DOMAIN_LIST := $(basename $(notdir $(SELECTED_XML_FILES)))

ifndef LANGS
# If LANGS is not defined within the command line, for output use only those files that are at least 60% translated.
# This check is made through the script 'po-selector'. However, since this operation is time consuming, it is performed
# only for a subset of targets. See variable 'CHECK_IF_TO_BE_TRANSLATED'.
ifdef CHECK_IF_TO_BE_TRANSLATED
# TO DO: rework the po-selector script so that 60% translation is not calculated on the single PO, but overall.
  LANGS := $(shell 50-tools/po-selector $(SELECTED_DOMAIN_LIST) | tee /dev/tty | sort -u)
  # If no language is suitable, print an error message and quit
  ifeq ($(strip $(LANGS)),)
  $(error No language passed selection!)
  endif
endif
endif

# TO DO: check if LANGSEN is still necessary
LANGSEN := $(LANGS) en

# The list of MO files necessary for the translation of the selected sources is generated as follows.
# For each selected language, the file name is built by adding the suffix '.lang.mo' to the list of
# selected domains, then it is added the prefix 'lang/po/' as dir name.
SELECTED_MO_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/po/,$(addsuffix .$(LANG).mo,$(SELECTED_DOMAIN_LIST))))

# The list of destination DC-, XML and ENT files is made by prefixing the lang code
XML_DEST_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/,$(SELECTED_XML_FILES)))
ENT_DEST_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/,$(SELECTED_ENT_FILES)))
SCHEMAS_XML_DEST_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/xml/,schemas.xml))
DC_DEST_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/,$(BOOKS_TO_TRANSLATE)))
#TO DO: select only necessary images via 'daps list-srcfiles'
IMAGE_DEST_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/,$(FULL_IMAGE_LIST)))

# The XML sources to be translated to create the requested output are retrieved by parsing the output of
# daps list-srcfiles, however when a book depends on — let's say — MAIN.*.xml (e.g. DC-SLES-tuning), validation
# and output generation fail because daps requires all XML files listed in the <xi:include href="file_name.xml"/>
# tags. To be on the safe side, create a symlink for all unselected sources prior to validation.
# The list of unselected sources is obtained by filtering out the selected sources from the full list.
# to that is prepended each selected lang dir.
# TO DO: check whether to obtain 100% output translation it is necessary to have also the additional files
# translated
UNSELECTED_XML_SOURCES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/,$(filter-out $(SELECTED_SOURCES),$(FULL_XML_LIST))))
UNSELECTED_ENT_SOURCES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/,$(filter-out $(SELECTED_SOURCES),$(FULL_ENT_LIST))))

# Functions to retrieve the path and file name of pdf/single html/text output
# TO DO: check why daps seems to ignore that xml files are translated into languages other than English
WHICH_PDF = $(shell 50-tools/output-retriever --dc-name $1 --pdf-name)
WHICH_HTML = $(shell 50-tools/output-retriever --dc-name $1 --html-name)
WHICH_TEXT = $(shell 50-tools/output-retriever --dc-name $1 --text-name)

# List of output files depending on selected languages and books to translate
PDF_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/,$(foreach BOOK, $(BOOKS_TO_TRANSLATE), $(call WHICH_PDF,$(BOOK)))))
SINGLE_HTML_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/,$(foreach BOOK, $(BOOKS_TO_TRANSLATE), $(call WHICH_HTML,$(BOOK)))))
TEXT_FILES := $(foreach LANG,$(LANGS),$(addprefix $(LANG)/,$(foreach BOOK, $(BOOKS_TO_TRANSLATE), $(call WHICH_TEXT,$(BOOK)))))

# TO DO: check if STYLEROOT is still necessary
ifndef STYLEROOT
  STYLEROOT := /usr/share/xml/docbook/stylesheet/opensuse2013-ns
endif

# TO DO: check if VERSION is still necessary
ifndef VERSION
  VERSION := unreleased
endif

# TO DO: check if DATE is still necessary
ifndef DATE
  DATE := $(shell date +%Y-%0m-%0d)
endif

# Allows for DocBook profiling (hiding/showing some text).
# TO DO: check if still necessary
LIFECYCLE_VALID := beta pre maintained unmaintained
ifndef LIFECYCLE
  LIFECYCLE := maintained
endif
ifneq "$(LIFECYCLE)" "$(filter $(LIFECYCLE),$(LIFECYCLE_VALID))"
  override LIFECYCLE := maintained
endif

DAPS_COMMAND_BASIC = daps -vv  
DAPS_COMMAND = $(DAPS_COMMAND_BASIC) -d 

ITSTOOL = itstool -i /usr/share/itstool/its/docbook5.its

# TO DO: check if still necessary
#XSLTPROC_COMMAND = xsltproc \
#--stringparam generate.toc "book toc" \
#--stringparam generate.section.toc.level 0 \
#--stringparam section.autolabel 1 \
#--stringparam section.label.includes.component.label 2 \
#--stringparam variablelist.as.blocks 1 \
#--stringparam toc.max.depth 3 \
#--stringparam show.comments 0 \
#--xinclude --nonet

# Fetch correct Report Bug link values, so translations get the correct
# version
#XPATHPREFIX := //*[local-name()='docmanager']/*[local-name()='bugtracker']/*[local-name()
#URL = `xmllint --noent --xpath "$(XPATHPREFIX)='url']/text()" xml/release-notes.xml`
#PRODUCT = `xmllint --noent --xpath "$(XPATHPREFIX)='product']/text()" xml/release-notes.xml`
#COMPONENT = `xmllint --noent --xpath "$(XPATHPREFIX)='component']/text()" xml/release-notes.xml`
#ASSIGNEE = `xmllint --noent --xpath "$(XPATHPREFIX)='assignee']/text()" xml/release-notes.xml`

all:
	@echo '$(PDF_FILES) | $(SINGLE_HTML_FILES) | $(TEXT_FILES)'
	@echo '$(FULL_IMAGE_LIST)'
#	@echo -ne "FULL_LANG_LIST: $(FULL_LANG_LIST)\n\nFULL_POT_LIST: $(FULL_POT_LIST)\n\nFULL_BOOK_LIST: $(FULL_BOOK_LIST)\n\n"
#	@echo -ne "SELECTED_SOURCES: $(SELECTED_SOURCES)\n\nSELECTED_XML_FILES: $(SELECTED_XML_FILES)\n\nSELECTED_ENT_FILES: $(SELECTED_ENT_FILES)\n\nSELECTED_DOMAIN_LIST: $(SELECTED_DOMAIN_LIST)\n\n"
#	@echo -ne "LANGS: $(LANGS)\n\n"

pot: $(FULL_POT_LIST)
50-pot/%.pot: xml/%.xml
	$(ITSTOOL) -o $@ $<

po: $(FULL_PO_LIST)

define update_po
 $(1)/po/%.$(1).po: 50-pot/%.pot
	if [ -r $$@ ]; then \
	msgmerge  --previous --update $$@ $$<; \
	else \
	msginit -o $$@ -i $$< --no-translator -l $(1); \
	fi
endef   

$(foreach LANG,$(FULL_LANG_LIST),$(eval $(call update_po,$(LANG))))

mo: $(SELECTED_MO_FILES)
%.mo: %.po
	msgfmt $< -o $@

# FIXME: Enable use of its:translate attribute in GeekoDoc/DocBook...
translate: $(XML_DEST_FILES) $(SCHEMAS_XML_DEST_FILES) $(ENT_DEST_FILES) $(UNSELECTED_XML_SOURCES) $(UNSELECTED_ENT_SOURCES) $(DC_DEST_FILES) $(IMAGE_DEST_FILES)

define translate_xml
 $$(XML_DEST_FILES): $(1)/xml/%.xml: $(1)/po/%.$(1).mo xml/%.xml
	if [ ! -d $$(@D) ]; then mkdir -p $$(@D); fi
	$$(ITSTOOL) -l $(1) -m $$< -o $$(@D) $$(filter %.xml,$$^)
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
	daps-xmlformat -i $$@
#	$(DAPS_COMMAND_BASIC) -m $@ validate

 %/xml/schemas.xml: xml/schemas.xml
	ln -s ../../$$< $$@
	
 $$(ENT_DEST_FILES): $(1)/xml/%.ent: xml/%.ent
	ln -s ../../$$< $$@
 
 ifneq ($$(strip $$(UNSELECTED_XML_SOURCES)),)
 $$(UNSELECTED_XML_SOURCES): $(1)/xml/%.xml: xml/%.xml
	ln -s ../../$$< $$@
 endif
 
 ifneq ($$(strip $$(UNSELECTED_ENT_SOURCES)),)
 $$(UNSELECTED_ENT_SOURCES): $(1)/xml/%.ent: xml/%.ent
	ln -s ../../$$< $$@
 endif

 $$(DC_DEST_FILES): $(1)/%: %
	cp $$< $$(@D)

 $$(IMAGE_DEST_FILES): $(1)/%: %
	if [ ! -d $$(@D) ]; then mkdir -p $$(@D); fi
	if [ ! -L $$@ -a ! -f $$@ ]; then ln -s ../../../../$$< $$@; fi
endef

$(foreach LANG,$(LANGS),$(eval $(call translate_xml,$(LANG))))

validate: translate
	@for DC_FILE in $(DC_DEST_FILES); do \
	echo -n "$$DC_FILE: "; \
	daps -d $$DC_FILE validate; \
	done

# TO DO: check if target 'translatedxml' is still necessary
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

pdf: validate $(PDF_FILES)

define generate_pdf
 $(2): $(1)
	$(DAPS_COMMAND) $< pdf 
 # TO DO: check if the following argument is still necessary
 # PROFCONDITION="general\;$(LIFECYCLE)"
endef
 
$(foreach LANG,$(LANGS),$(foreach BOOK, $(BOOKS_TO_TRANSLATE),$(eval $(call generate_pdf,$(BOOK),$(addprefix $(LANG)/,$(call WHICH_PDF,$(BOOK)))))))

single-html: validate $(SINGLE_HTML_FILES)

define generate_html
 $(2): $(1)
	$(DAPS_COMMAND) $< html --single 
 # TO DO: check if the following arguments are still necessary
 # --stringparam "homepage='https://www.opensuse.org'" \
 # PROFCONDITION="general\;$(LIFECYCLE)"
endef

$(foreach LANG,$(LANGS),$(foreach BOOK, $(BOOKS_TO_TRANSLATE),$(eval $(call generate_html,$(BOOK),$(addprefix $(LANG)/,$(call WHICH_HTML,$(BOOK)))))))

text: validate $(TEXT_FILES)

define generate_text
 $(2): $(1)
	$(DAPS_COMMAND) $< text
 # TO DO: check if the following argument is still necessary
 # PROFCONDITION="general\;$(LIFECYCLE)"
endef

$(foreach LANG,$(LANGS),$(foreach BOOK, $(BOOKS_TO_TRANSLATE),$(eval $(call generate_text,$(BOOK),$(addprefix $(LANG)/,$(call WHICH_TEXT,$(BOOK)))))))

clean_po_temp:
	rm -rf $(foreach LANG,$(FULL_LANG_LIST),$(addprefix $(LANG),/po/*.po~))
	
clean_mo:
	rm -rf $(FULL_MO_LIST)

clean_pot:
	rm -rf $(FULL_POT_LIST)

clean: clean_po_temp clean_mo
	rm -rf $(foreach LANG,$(FULL_LANG_LIST),$(addprefix $(LANG),/xml/))
	rm -rf $(foreach LANG,$(FULL_LANG_LIST),$(addprefix $(LANG)/,$(FULL_BOOK_LIST)))
	rm -rf $(foreach LANG,$(FULL_LANG_LIST),$(addprefix $(LANG),/build/))
	rm -rf build/

cleanall: clean clean_pot

