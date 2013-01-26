#!/usr/bin/python2
# -*- coding: UTF-8 -*-

import gi
from gi.repository import Gtk
import subprocess, sys, os
import threading
import gettext
import locale

# # Algunas cosas para gettext (para las traducciones)
APP_NAME="welcn"




WELCN_DIR = '/usr/share/welcn/'


class main():


	def __init__(self):


		builder = Gtk.Builder()

		#Translation stuff

		#Get the local directory since we are not installing anything
		self.local_path = os.path.realpath(os.path.dirname(sys.argv[0]))
		# Init the list of languages to support
		langs = []
		#Check the default locale
		lc, encoding = locale.getdefaultlocale()
		if (lc):
			#If we have a default, it's the first in the list
			langs = [lc]
		# Now lets get all of the supported languages on the system
		language = os.environ.get('LANG', None)
		if (language):
			"""langage comes back something like en_CA:en_US:en_GB:en
			on linuxy systems, on Win32 it's nothing, so we need to
			split it up into a list"""
			langs += language.split(":")
		"""Now add on to the back of the list the translations that we
		know that we have, our defaults"""
		langs += ["en_US"]

		"""Now langs is a list of all of the languages that we are going
		to try to use.  First we check the default, then what the system
		told us, and finally the 'known' list"""

		gettext.bindtextdomain(APP_NAME, self.local_path)
		gettext.textdomain(APP_NAME)
		# Get the language to use
		self.lang = gettext.translation(APP_NAME, self.local_path
			, languages=langs, fallback = True)
		"""Install the language, map _() (which we marked our
		strings to translate with) to self.lang.gettext() which will
		translate them."""
		_ = self.lang.gettext



		
		builder.add_from_file(WELCN_DIR + "welcn.ui")
		
		
		#### Language and Keymap window
		self.window = builder.get_object("window1")
		self.label_welcome = builder.get_object("label1")
		self.label_info = builder.get_object("label2")
		self.button_try = builder.get_object("button1")
		self.button_cli_installer = builder.get_object("button2")
		self.button_gra_installer = builder.get_object("button3")
		self.button_try.set_label(_("Try it"))
		self.button_cli_installer.set_label(_("CLI Installer"))
		self.button_gra_installer.set_label(_("Graphical Installer"))
		self.label_welcome.set_label(_("Welcome to Cinnarch"))
		self.label_info.set_markup(_('<b>You can try Cinnarch without modify your hard drive, just click on "Try it".\nIf you want to install the system to your PC, use one of the two installer options.</b>'))



		self.window.connect("delete-event", Gtk.main_quit)
		builder.connect_signals(self)
		self.window.set_title(_('Welcome!'))
		self.window.set_position(Gtk.WindowPosition.CENTER)


		self.window.show_all()

	def on_button1_clicked(self, widget, data=None):
		Gtk.main_quit()

	def on_button2_clicked(self, widget, data=None):
		subprocess.Popen(["cinnarch-setup"])
		sys.exit(0)





if __name__ == '__main__':
	main()
	Gtk.main()