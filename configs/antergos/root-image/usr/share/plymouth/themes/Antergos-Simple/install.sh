#! /bin/bash
set -e

# Set tab to 2.
# This script installs the Plymouth theme in the themes sub-directory under Plymouth's
# directory.
#
# 
# Modified version of Grub Theme Install Script Version 2.1 from Towheed Mohammed
# Adapted for use with Plymouth Themes by Dustin Falgout <dustinfalgout@gmail.com> 2013

# This is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This software is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details at <http://www.gnu.org/licenses/>.

# Set properties of theme
# The theme will be installed in a dir with this name.
theme_name='Antergos-Simple'

# Filename of theme definition file.
theme_definition_file='Antergos-Simple.plymouth'

# Filename of theme script.
theme_script='antergos-script.script'

#Set variables for color.
bold='\E[1m'
red_bold='\E[1;31m'
blue_bold='\E[1;34m'
cyan_bold='\E[1;36m'
green_bold='\E[1;32m'
normal='\E[0m'

msg_yes_no="[${green_bold} y${normal}es ${green_bold}n${normal}o ] "
msg_overwrite_create="[${green_bold} o${normal}verwrite ${green_bold}c${normal}reate ] "

# Directory containing theme files to install.
self=$(dirname $0)

# Default installtion of plymouth.
theme_prefix_default="/usr/share/plymouth"

# Create the theme's directory.  If directory already exists, ask the user if
# they would like to overwrite the contents with the new theme or create a new
# theme directory.
theme_dir="${theme_prefix_default}/themes/${theme_name}"

mkdir -p "${theme_dir}"
echo -e "Installing theme to: ${cyan_bold}${theme_dir}${normal}."

# Copy the theme's files to the theme's directory.
for i in ${self}/* ; do
	cp -r "${i}" "${theme_dir}/$(basename "${i}")"
done

# Set the theme.
plymouth-set-default-theme -R Antergos-Simple

exit 0
