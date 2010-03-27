# Makefile for installing ssssh

.PHONY: default install clean

DEST = /usr/local/bin

BASH_SCRIPTS = ssssh.bash


default::
	@echo 'use "make install" to install into $(DEST)'

install::
	for f in $(BASH_SCRIPTS); do install $$f $(DEST)/$${f%.*}; done
	ln -sf ssssh $(DEST)/ssssh-pull
	ln -sf ssssh $(DEST)/ssssh-push

clean::
	-rm -f *~
