V=3

INSTALL_FILES=$(wildcard archiso/initcpio/install/*)
HOOKS_FILES=$(wildcard archiso/initcpio/hooks/*)
SCRIPT_FILES=$(wildcard archiso/initcpio/script/*)

INSTALL_DIR=$(DESTDIR)/usr/lib/initcpio/install
HOOKS_DIR=$(DESTDIR)/usr/lib/initcpio/hooks
SCRIPT_DIR=$(DESTDIR)/usr/lib/initcpio



all:

install: install-program install-initcpio install-examples

install-program:
	install -D -m 755 archiso/mkarchiso $(DESTDIR)/usr/bin/mkarchiso

install-initcpio:
	install -d $(SCRIPT_DIR) $(HOOKS_DIR) $(INSTALL_DIR)
	install -m 755 -t $(SCRIPT_DIR) $(SCRIPT_FILES)
	install -m 644 -t $(HOOKS_DIR) $(HOOKS_FILES)
	install -m 644 -t $(INSTALL_DIR) $(INSTALL_FILES)

install-examples:
	install -d -m 755 $(DESTDIR)/usr/share/antergos-iso/
	cp -a --no-preserve=ownership configs $(DESTDIR)/usr/share/antergos-iso/


dist:
	git archive --format=tar --prefix=antergos-iso-$(V)/ v$(V) | gzip -9 > antergos-iso-$(V).tar.gz
	gpg --detach-sign --use-agent antergos-iso-$(V).tar.gz

.PHONY: install install-program install-initcpio install-examples dist
