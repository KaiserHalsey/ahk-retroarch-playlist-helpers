;### AUTOHOTKEY SCRIPT TO SORT MAME ROMS BY GENRE
;### By markwkidd and based on work by libretro forum users roldmort, Tetsuya79, and Alexandra
;### Icon by Alexander Moore @ http://www.famfamfam.com/

;---------------------------------------------------------------------------------------------------------
#NoEnv                         ;### Recommended by AutoHotKey for performance and compatibility.
#Warn                          ;### Enable warnings to assist with detecting common errors.
SendMode Input                 ;### Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%    ;### Ensure a consistent starting directory.
SetBatchLines -1               ;### Don't yield CPU to other processes (remove if there are CPU issues).
;---------------------------------------------------------------------------------------------------------

#include retroarch-playlist-helper-lib.ahk

global app_title                         := "Simple Arcade Category Sorter"

;### INITIALIZE GLOBAL VARIABLES
;### Leave blank to prompt for all values in GUI
;### Enter values in the script to serve as defaults in GUI

global rom_path                         := ""
global rom_path_label                   := "Local Arcade ROM set source path"

global output_path                      := ""
global output_path_config_label         := "Local destination path for copied ROM sets"
global output_path_config_desc          := "Will not output to the 'root folder' of a drive (e.g. c:\)"

global dat_path                         := "" ;### path to an arcade XML DAT file

global catver_path_label                := "Local path to catver.ini"
global catver_path_desc                 := "The catver file should be the same version as the arcade ROM sets being processed"
global catver_path                      := ""

global category_list                    := "" ;### eventually populated with catver data

global include_filter	                := ""
global include_list_label               := "Select one or more categories to include"
global manual_include_filter_label      := "Enter a manual inclusion filter (overrides selection box)"
global manual_include_filter_desc       := "Categories should be separated by a pipe character, for example:`nShooter|Flying Horizontal|Maze"
global manual_include_filter            := ""

global exclude_filter                   := ""
global exclude_list_label               := "Select one or more categories to exclude (optional)"
global manual_exclude_filter_label      := "Enter a manual exclusion filter (overrides selection box)"
global manual_exclude_filter_desc       := "Categories should be separated by a pipe character, for example:`nShooter|Flying Horizontal|Maze"
global manual_exclude_filter            := ""

global bundle_BIOS_files                := True   ;### always include BIOS files **as designated in the DAT**
global bundle_mature_files              := False
global exclude_clones                   := False  ;### always exclude clones **as deignated in the DAT** (uses 'cloneof' tag)
global exclude_mature_titles            := False 
global exclude_CHD_titles               := False
global exclude_non_running_titles       := True

global eol_character                    := "`n"   ;### RetroArch default is UNIX end of line although Windows style works
global path_delimiter                   := "\"    ;### Default to Windows paths
global trigger_generation				:= False
;---------------------------------------------------------------------------------------------------------

Main()
ExitApp

Main() {
	GatherConfigData:
	PrimarySettingsGUI()        ;### Prompt the user to enter the configuration 
	WinWaitClose

	StripFinalSlash(rom_path)   ;## Remove any trailing forward or back slashes from user-provided paths

	;### Exit if these files/folders don't exist or are set incorrectly
	if !FileExist(rom_path) {
		MsgBox,,Path Error!, ROM directory does not exist:`n%rom_path%
		Goto, GatherConfigData
	} else if (!FileExist(catver_path)) {
		MsgBox,,Path Error!,catver.ini file not found:`n%catver_path%
		Goto, GatherConfigData
	} else if (!FileExist(dat_path)) {
		MsgBox,,Path Error!, DAT file not found:`n%dat_path%
		Goto, GatherConfigData
	}

	ROMFileList    := "" ;### (re)initialize - user may have returned to this point in the process
	category_list  := "" ;### (re)initialize
	number_of_roms := 0  ;### (re)initialize
	
	Loop, Files, %rom_path%\*.* ;### just count the files
	{
		number_of_roms := A_index
	}
	
	Progress, A M T, Parsing catver.ini`, DAT`, and ROM folder., , %app_title%
	Progress, 0
	
	DAT_array := ""
	BuildArcadeDATArray(dat_path, DAT_array)
	percent_parsed := 30
	Progress, %percent_parsed%
	
	;### store list of ROMs with full path, dat modifiers, and categories in new array
	
	parsed_ROM_array := Object()
	
	Loop, Files, %rom_path%\*.*
	{
		SplitPath, A_LoopFileName,,,,ROM_filename_no_ext
		IniRead, ROM_entry_categories, %catver_path%, Category, %ROM_filename_no_ext%, **Uncategorized**
		
		DAT_entry := DAT_array[ROM_filename_no_ext]
		is_clone  := DAT_array.iscloneof
		needs_CHD := DAT_array.needs_CHD

 		percent_parsed := 30 + (Round(100 * (A_index / number_of_roms)) - 30)
		Progress, %percent_parsed%
	
		;### Mature tag looks like this in older catver.ini: *Mature*
        ;### looks like this in newer catver.ini: * Mature *
		is_mature       := False		
		if(InStr(ROM_entry_categories, " *Mature*") || InStr(ROM_entry_categories, " * Mature *")) {
			is_mature    := True
			flag_index := InStr(ROM_entry_categories, "*") - 2
			ROM_entry_categories := Trim(SubStr(ROM_entry_categories, 1, flag_index))
		}
			
		flag_index := InStr(ROM_entry_categories, " / ")
		if(flag_index) {
			primary_ROM_category := Trim(SubStr(ROM_entry_categories, 1, flag_index))
		} else {
			primary_ROM_category := Trim(ROM_entry_categories)
		}

		is_runnable     := DAT_array[ROM_filename_no_ext].runnable	
		if(primary_ROM_category == "Unplayable") {
			is_runnable := False
		}
		
		;### Build a list of all the categories represented in the catver.ini file
		IfNotInString, category_list, %primary_ROM_category%|
		{
			category_list .= primary_ROM_category . "|"
		}
		IfNotInString, category_list, %ROM_entry_categories%|
		{
			category_list .= ROM_entry_categories . "|"
		}
		
		;### using ROM_filename_no_ext . "" as the index seems to be necessary to avoid
		;### AHK from interpresting numberic romsets names as number (eg 005, 1941 etc)
		parsed_ROM_array[ROM_filename_no_ext] := { path:(ROM_path . "\" . A_LoopFileName)
		                                         , is_BIOS:(DAT_array.isbios)
												 , is_clone:(DAT_array.iscloneof)
												 , is_mature:is_mature
												 , is_runnable:is_runnable
												 , needs_CHD:needs_CHD
												 , primary_category:primary_ROM_category
												 , full_category:ROM_entry_categories}		
	}

	Progress, Off
	
	ShowFilterSelectGUI:
	output_path    := "" ;### (re)initialize
	include_filter := ""
	exclude_filter := ""
	
	FilterSelectGUI()
	WinWaitClose
	
	if(!trigger_generation) {	;### For example if the "Return" button or window close chrome has been used
		Goto, GatherConfigData
	}

	if (output_path == "") {
		MsgBox,,Path Error!, Output path is blank
		Goto, ShowFilterSelectGUI
	} 
	StripFinalSlash(output_path)    ;## Remove any trailing forward or back slashes from user-provided paths
	FileCreateDir, %output_path%    ;### create output folder if it doesn't exist
	
	include_filter := "|" . include_filter . "|" ;### pipe characters @ beginning and end to help match pattern		

	if (exclude_filter == "") {
		;### It's OK if there's no exclusion filter
	} else {
		exclude_filter := "|" . exclude_filter . "|"
	}
		
	current_ROM_index := 0
	Progress, A M T, Filtering and copying ROMs and CHDs., Initializing, %app_title%

	For romset_index, romset_details in parsed_ROM_array
	{
		current_ROM_index          += 1
		current_ROM_set_name       := romset_details.romset_name
		current_ROM_path           := romset_details.path
		ROM_matches_inclusion_list := False
		ROM_filename_with_ext      := ""				
		SplitPath, current_ROM_path, ROM_filename_with_ext,,,
		
		if(exclude_clones && romset_details.is_clone) {
			continue
		}
		if(exclude_mature_titles && romset_details.is_mature){
			continue
		}
		if(exclude_CHD_titles && romset_details.needs_CHD) {
			continue
		}
		if(exclude_non_running_titles && !romset_details.is_runnable) {
				continue
		}
		
		if(bundle_BIOS_files && romset_details.is_bios) {
			ROM_matches_inclusion_list := True
		} else if(bundle_mature_files && romset_details.is_mature) {
			ROM_matches_inclusion_list := True
		} else {

			check_category_query := "|" . romset_details.primary_category . "|"
			If(InStr(include_filter, check_category_query)) {
				ROM_matches_inclusion_list := True
			} else if(InStr(exclude_filter, check_category_query)) {
				continue
			}
			
			check_category_query := "|" . romset_details.full_category . "|"
			If(InStr(include_filter, check_category_query)) {
				ROM_matches_inclusion_list := True
			} else if(InStr(exclude_filter, check_category_query)) {
				continue
			}				
		}			

		if(!ROM_matches_inclusion_list) {
			continue
		}
		percent_parsed := Round(100 * (current_ROM_index / number_of_roms))
		Progress, %percent_parsed%, Filtering and copying ROMs and CHDs., %current_ROM_set_name%, %app_title%
		
		;MsgBox current_rom path:%current_ROM_path%`n`noutput: %output_path%
		
		FileCopy, %current_ROM_path%, %output_path%, 0 ;### do not overwrite existing files

		if(romset_details.needs_CHD) {
			;### check for CHD folders
			CHD_source_path      := ROM_path . "\" . current_ROM_set_name
			CHD_destination_path := output_path . "\" . current_ROM_set_name
			
			if(FileExist(CHD_source_path)) {
				If(!FileExist(CHD_destination_path)) {
					FileCreateDir, %CHD_destination_path%
				}
				FileCopy, %CHD_source_path%\*.*, %CHD_destination_path%\*.*, False
			}
		}

	}
	Progress, Off
	MsgBox,,%app_title%,Copy complete. Click OK to return to menu.
	Goto, ShowFilterSelectGUI
	
}

;---------------------------------------------------------------------------------------------------------

PrimarySettingsGUI()
{
	DetectHiddenWindows, Off

	Gui, path_entry_window: new
	Gui, Default
	Gui, +LastFound
	
	;### Primary options
	Gui, Font, s12 w700, Verdana
	Gui, Add, Groupbox, w580 h195 Section, Configure sources

		;### ROM storage location
		Gui, Font, s10 w700, Verdana
		Gui, Add, Text, xs8 ys22 w550, %rom_path_label%
		Gui, Font, s10 w400, Verdana
		Gui, Add, edit, w400 xs8 y+2 vrom_path, %rom_path%
		
		;### Arcade DAT file location
		Gui, Font, s10 w700, Verdana
		Gui, Add, Text, w550 xs8 y+10, Local path to MAME XML DAT file
		Gui, Font, Normal s10 w400, Verdana
		Gui, Add, edit, w400 xs8 y+0 vdat_path, %dat_path%

		;### catver.ini file location
		Gui, Font, s10 w700, Verdana
		Gui, Add, Text, xs8 y+10, %catver_path_label%
		Gui, Font, Normal s10 w400, Verdana
		Gui, Add, Text, xs8 y+0 w550, %catver_path_desc%
		Gui, Add, edit, w400 xs8 y+0 vcatver_path, %catver_path%

	;### Buttons
	Gui, Font, s10 w700, Verdana
	Gui, Add, button, w100 xm+240 y+24 gDone, Next Step
	Gui, Add, button, w100 x+20 yp gExit, Exit

	Gui, Show, w600, %app_title%
	return WinExist()

	Done:
	{
		Gui,submit,nohide
		Gui,destroy
		return
	}

	path_entry_windowGuiClose:
	Exit:
	{
		Gui path_entry_window:destroy
		ExitApp
	}
}

;---------------------------------------------------------------------------------------------------------

FilterSelectGUI() {

	DetectHiddenWindows, Off
	Gui, category_selection_window: new
	Gui, Default
	Gui, +LastFound

	;### BEGIN LEFT COLUMN

	;### output path
	Gui, Font, s12 w700, Verdana
	Gui, Add, Groupbox, w490 Section xm0 ym0 h70,%output_path_config_label%
	Gui, Font, s10 w400, Verdana
	Gui, Add, edit, w470 xs8 ys+24 voutput_path, %output_path%
	Gui, Add, Text, xs8 y+0 w470, %output_path_config_desc%
	
	;### include filter
	Gui, Font, s12 w700, Verdana
	Gui, Add, Groupbox, w490 xm0 ys75 h420 Section,%include_list_label%
		Gui, Font, s12 w400, Verdana
		Gui, Add, ListBox, Sort 8 vinclude_filter xs9 ys+24 w470 h280, %category_list%

		;### manual include filter
		Gui, Font, s10 w700, Verdana
		Gui, Add, Text, xs8 y+10, %manual_include_filter_label%
		Gui, Font, Normal s10 w400, Verdana
		Gui, Add, Edit, r3 xs8 w470 y+0 vmanual_include_filter, %manual_include_filter%
		Gui, Add, Link, xs8 w470 y+0, %manual_include_filter_desc%
		
	;### other include filters
	Gui, Font, s12 w700, Verdana
	Gui, Add, Groupbox, xm0 y+14 w490 h110 Section, Other filters
	Gui, Font, s10 w400, Verdana
	Gui, Add, Checkbox, xs8 ys24 w470 vbundle_BIOS_files Checked%bundle_BIOS_files%, Copy all BIOS files (as listed in the DAT)
	Gui, Add, Checkbox, xs8 y+4 w470 vbundle_mature_files Checked%bundle_mature_files%, Copy all Mature entries
	
	
	;### BEGIN RIGHT COLUMN
	Gui, Font, s12 w700, Verdana
	Gui, Add, Groupbox, w490 Section x+20 ym0 h70,Generate manual filters
	Gui, Font, s10 w400, Verdana
	Gui, Add, Text, xs8 ys24 w300, Translate inclusion and exclusion selections into manual filters.
	Gui, Add, button, w150 x+20 ys24 gGenerateManualFilters, Generate filters

	;### exclude filter
	Gui, Font, s12 w700, Verdana
	Gui, Add, Groupbox, w490 xs0 ys75 h420 Section,%exclude_list_label%
		Gui, Font, s12 w400, Verdana
		Gui, Add, ListBox, Sort 8 vexclude_filter xs9 ys+24 w470 h280, %category_list%

		;### manual exclude filter entry
		Gui, Font, s10 w700, Verdana
		Gui, Add, Text, xs8 y+10, %manual_exclude_filter_label%
		Gui, Font, Normal s10 w400, Verdana
		Gui, Add, Edit, r3 xs8 w470 y+0 vmanual_exclude_filter, %manual_exclude_filter%
		Gui, Add, Link, xs8 w470 y+0, %manual_exclude_filter_desc%
		
	;### other exclude filters
	Gui, Font, s12 w700, Verdana
	Gui, Add, Groupbox, xs0 y+14 w490 h110 Section, Other filters
	Gui, Font, s10 w400, Verdana
	Gui, Add, Checkbox, xs8 ys24 w470 vexclude_clones Checked%exclude_clones%, Always exclude entries tagged as clones
	Gui, Add, Checkbox, xs8 y+4 w470 vexclude_mature_titles Checked%exclude_mature_titles%, Always exclude mature entries
	Gui, Add, Checkbox, xs8 y+4 w470 vexclude_CHD_titles Checked%exclude_CHD_titles%, Always exclude entries with CHDs
	Gui, Add, Checkbox, xs8 y+4 w470 vexclude_non_running_titles Checked%exclude_non_running_titles%, Always exclude non-runnable entries


	;### Buttons
	Gui, Font, s10 w700, Verdana
	Gui, Add, button, w200 xs0 y+20 gCopyROMs, Copy Matching ROMs
	Gui, Add, button, w100 x+20 yp gExit_Category_Select, Return

	Gui, show, w1020, %app_title%
	return WinExist()

	GenerateManualFilters:
	{
		Gui, submit, nohide
		GuiControl,, manual_include_filter, %include_filter%
		GuiControl,, manual_exclude_filter, %exclude_filter%
		Return
	}
	CopyROMs:
	{
		Gui,submit,nohide
		if (manual_include_filter != "") {
			include_filter := manual_include_filter
		} else if (include_filter == "") {
			;## not a problem if they're using the 'other' include filters
		}

		if (manual_exclude_filter != "") {
			exclude_filter := manual_exclude_filter
		} 
	
		trigger_generation := True
		Gui category_selection_window:destroy
		Return
	}

	category_selection_windowGuiClose:
	Exit_Category_Select:
	{
		trigger_generation := False
		Gui category_selection_window:destroy
		Return
	}
}