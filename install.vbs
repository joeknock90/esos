option explicit

' Make sure the scripting host is cscript.exe
dim sh_engine, shell_app
sh_engine = lcase(mid(wscript.fullname, instrrev(wscript.fullname, "\") + 1))
if not sh_engine = "cscript.exe" then
    set shell_app = createobject("shell.application")
    shell_app.shellexecute "cscript.exe", chr(34) & wscript.scriptfullname & chr(34) & " uac", "", "runas", 1
    wscript.quit
end if

wscript.echo "*** Enterprise Storage OS Install Script ***"
wscript.echo ""

' Setup
on error resume next
dim wsh_shell, file_sys, wmi_service
set wsh_shell = createobject("wscript.shell")
set file_sys = createobject("scripting.filesystemobject")
set wmi_service = getobject("winmgmts:\\.\root\cimv2")
wsh_shell.currentdirectory = file_sys.getparentfoldername(wscript.scriptfullname)

' Settings
dim install_common, base_path, md5sum_prog, sha256sum_prog, dd_prog, _
    sevenzip_prog
install_common = "install_common"
base_path = wsh_shell.currentdirectory
md5sum_prog = base_path & "\checksum_utils\md5sum.exe"
sha256sum_prog = base_path & "\checksum_utils\sha256sum.exe"
dd_prog = base_path & "\dd-0.6beta3\dd.exe"
sevenzip_prog = base_path & "\7zip-9.20\7z.exe"

' Verify the checksums
dim md5sum_cmd, sha256sum_cmd
wscript.echo "### Verifying checksums..."
md5sum_cmd = md5sum_prog & " -w -c dist_md5sum.txt"
exec_cmd wsh_shell, md5sum_cmd
sha256sum_cmd = sha256sum_prog & " -w -c dist_sha256sum.txt"
exec_cmd wsh_shell, sha256sum_cmd
wscript.echo

' List available disks
dim diskpart_list_cmd
wscript.echo "### Here is a list of disks on this machine:"
diskpart_list_cmd = "%comspec% /c ""echo list disk"" | diskpart.exe"
exec_cmd wsh_shell, diskpart_list_cmd
wscript.echo
wscript.echo

' Get USB flash drive (volume) choice from user
dim disk_num
wscript.echo "### Please type the disk number of your USB flash drive:"
disk_num = wscript.stdin.readline
wscript.echo
wscript.echo
if disk_num = "" then
    exit_app
end if

' Get confirmation from user
dim diskpart_clean_cmd, vol_path, confirm_write, cwd_folder, zipped_image, image_file, file, dd_write_cmd
wscript.echo "### Proceeding will completely wipe disk " & disk_num & ". Are you sure?"
confirm_write = wscript.stdin.readline
if confirm_write = "yes" or confirm_write = "y" then
    ' Clean the disk (removes partitions) using diskpart
    diskpart_clean_cmd = "%comspec% /c ""echo select disk " & _
        disk_num & "◙ clean"" | diskpart.exe"
    exec_cmd wsh_shell, diskpart_clean_cmd
    wscript.echo
    wscript.echo
    ' Set the device path/name for dd
    vol_path = "\\?\device\harddisk" & disk_num & "\partition0"
    ' Find the image file name
    set cwd_folder = file_sys.getfolder(".")
    for each file in cwd_folder.files
        if file_sys.getextensionname(file) = "bz2" then
            set zipped_image = file
            exit for
        end if
    next
    if zipped_image <> "" then
        ' Extract image
        wscript.echo "### Extracting the image file..."
        exec_cmd wsh_shell, sevenzip_prog & " x -bd -y " & zipped_image
        image_file = replace(zipped_image, ".bz2", "")
        wscript.echo
        wscript.echo
        ' Write the image file
        wscript.echo "### Writing " & image_file & " to " & _
            vol_path & "; this may take a while..."
        dd_write_cmd = dd_prog & " if=" & image_file & " of=" & _
            vol_path & " bs=1M"
        exec_cmd wsh_shell, dd_write_cmd
        wscript.echo
        wscript.echo "### It appears the image was successfully written to disk (check for error messages)!"
    else
        wscript.echo "ERROR: No image file was found!"
        wscript.echo
        exit_app
    end if
else
    ' User bailed
    wscript.echo
    exit_app
end if

' We're all done, users can install RAID tools in the ESOS instance
wscript.echo
wscript.echo
wscript.echo "*** RAID controller management utilities are now installed " & _
    "using the 'raid_tools.py' script in a running ESOS instance. ***"
wscript.echo
wscript.echo "### ESOS USB drive installation complete!"
wscript.echo "### You may now remove and use your ESOS USB drive."

' Done
wscript.echo
exit_app


sub exit_app
    wscript.stdout.write "Press the ENTER key to exit..."
    wscript.stdin.readline
    wscript.quit
end sub


function read_all(shell_exec)
    ' Check/read stdout
    if not shell_exec.stdout.atendofstream then
        read_all = shell_exec.stdout.readall
        exit function
    end if
    ' Check/read stderr
    if not shell_exec.stderr.atendofstream then
        read_all = shell_exec.stderr.readall
        exit function
    end if
    read_all = -1
end function


function exec_cmd(wsh_shell, cmd_string)
    dim all_input, try_count, shell_exec
    all_input = ""
    try_count = 0
    ' Execute the command
    set shell_exec = wsh_shell.exec(cmd_string)
    ' Loop until we have all command output (or timeout)
    do while true
        dim input
        input = read_all(shell_exec)
        if -1 = input then
            if try_count > 10 and shell_exec.status = 1 then
                exit do
            end if
            try_count = try_count + 1
            wscript.sleep 100
        else
            all_input = all_input & input
            try_count = 0
        end if
    loop
    ' Print all command output and quit if non-zero exit returned
    wscript.echo all_input
    if shell_exec.exitcode <> 0 then
        wscript.echo "ERROR: '" & cmd_string & "' returned a non-zero exit code!"
        wscript.echo
        exit_app
    end if
end function

