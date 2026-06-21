-- Clinj.app — one-click Mac cleaner (Dock / Finder app)
-- Compiled to an .app by install.sh via osacompile. Shells out to ~/.clinj/bin/clinj.sh.

property appTitle : "Clinj"

on clinjHome()
	return (POSIX path of (path to home folder)) & ".clinj"
end clinjHome

on bin()
	return quoted form of (clinjHome() & "/bin/clinj.sh")
end bin

on runEngine(flags)
	-- runs the engine in --report mode and returns its one-line summary
	return (do shell script "/bin/bash " & bin() & " " & flags & " --report")
end runEngine

on notify(msg)
	display dialog msg buttons {"OK"} default button "OK" with title appTitle with icon note
end notify

on main()
	set theChoice to (choose from list {¬
		"🧼  Clean Now  (safe)", ¬
		"⚡  Deep Clean  (max space)", ¬
		"🧠  RAM Boost", ¬
		"🔍  Preview  (dry run)", ¬
		"🗂  Reclaim Claude VM bundles  (13 GB)", ¬
		"⚙️  Settings", ¬
		"⏱  Schedule auto-runs"} ¬
		with prompt "What would you like to do?" ¬
		with title appTitle default items {"🧼  Clean Now  (safe)"})
	if theChoice is false then return -- user cancelled
	set theChoice to item 1 of theChoice

	if theChoice starts with "🧼" then
		notify("Result:" & return & return & runEngine(""))

	else if theChoice starts with "⚡" then
		display dialog "Deep Clean also clears Chrome ML caches, Xcode archives & device support." & return & return & ¬
			"Your apps keep working and your files are untouched — some caches simply re-download as needed." ¬
			buttons {"Cancel", "Deep Clean"} default button "Deep Clean" with title appTitle with icon caution
		if button returned of result is "Deep Clean" then notify("Result:" & return & return & runEngine("--aggressive"))

	else if theChoice starts with "🧠" then
		ramBoost()

	else if theChoice starts with "🔍" then
		notify(runEngine("--aggressive --dry-run"))

	else if theChoice starts with "🗂" then
		reclaimVMs()

	else if theChoice starts with "⚙️" then
		do shell script "/usr/bin/open -t " & quoted form of (clinjHome() & "/etc/clinj.conf")

	else if theChoice starts with "⏱" then
		scheduleMenu()
	end if
end main

on ramBoost()
	set memBefore to (do shell script "/bin/bash " & bin() & " --mem") as integer
	try
		do shell script "/usr/sbin/purge" with administrator privileges
	on error
		notify("RAM Boost cancelled.")
		return
	end try
	set memAfter to (do shell script "/bin/bash " & bin() & " --mem") as integer
	set freed to memAfter - memBefore
	if freed < 0 then set freed to 0
	notify("🧠 RAM Boost done." & return & return & ¬
		"Free memory: " & memBefore & " MB → " & memAfter & " MB" & return & ¬
		"Reclaimed ~" & freed & " MB" & return & return & ¬
		"(macOS reclaims memory automatically too, so gains are usually modest.)")
end ramBoost

on reclaimVMs()
	display dialog "Claude's sandbox VM bundles can use 13 GB+." & return & return & ¬
		"Removing them is safe — they re-download automatically the next time you use Claude's sandbox. Continue?" ¬
		buttons {"Cancel", "Reclaim"} default button "Cancel" with title appTitle with icon caution
	if button returned of result is "Reclaim" then notify("Result:" & return & return & runEngine("--vm-bundles"))
end reclaimVMs

on scheduleMenu()
	set pick to (choose from list {"Daily", "Every 3 days", "Weekly", "Off"} ¬
		with prompt "How often should Clinj auto-run a safe cleanup?" with title appTitle default items {"Daily"})
	if pick is false then return
	set pick to item 1 of pick
	if pick is "Daily" then set arg to "daily"
	if pick is "Every 3 days" then set arg to "3day"
	if pick is "Weekly" then set arg to "weekly"
	if pick is "Off" then set arg to "off"
	do shell script "/bin/bash " & quoted form of (clinjHome() & "/bin/schedule.sh") & " " & arg
	notify("Auto-run schedule set to: " & pick)
end scheduleMenu

main()
