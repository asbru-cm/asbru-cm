# Coding Standard

This coding standard consists of recommendations when contributing to the Ásbrú Connection Manager project.  Recommendations are meant to provide guidance that, when followed, should improve the safety, reliability, and security of the project.

## Coding guidelines

* Use spaces as indentation (no tabs).
* Use 4 spaces per indentation level.
* No trailing white space.
* Explicit if statements:
  - No use of:
    - `unless`
    - reversed if `next if $true;`
    - non explicit conditional expressions
      - `($a) && ($b) and print "do this if both variables are true";`
* Ternary operator for assigment is allowed as long as the code does not obfuscate.
  - `my $value = ($exists) ? $exists : 1;`
* Use of strings with interpolation.
  - Example: `$CNF_DIR = "$ENV{'HOME'}/.config/pac";`
* Nested parenthesis should be together unless you feel that a separation makes code more readable.
* All conditional blocks, Loops must be on different lines, even if it is one statement in the block.
* Local variables should be declared at the beginning of a function block, and if they are not initialized, they could be declared as one line.
    * `my ($var1, $var2, $var3);`
    * Avoid declaring them in the middle of the block, unless is going to be used as a temporary variable inside an inner block.
* Rules might be bent from time to time, when brings something valuable to the code over formatting.
* Function naming
    * Use camel case, example : myLongNameFunction
    * Add an undersocore to local function names : _myPrivateFunction

## Documentation guidelines

* At the end of each script the `__END__` marker should be added
  - This marker will tell the compiler to stop processing the file from that point onward.
  - Allowing to write extensive documentation without being processed by the compiler.
* After the end marker, documentation can be added in pod format, to allow perldoc to format and present information on the screen or to export to other formats.

### Basic pod (Plain Old Documentation)

**Common Sections**, as found in all CPAN documentation

* **NAME** module or script name, a dash and a short description.
* SYNOPSIS shows example usage.
* **DESCRIPTION** long description of what the module does and lists functions.
* **BUGS or CAVEATS** about bugs or issues the user should know about.
* ACKNOWLEDGEMENTS thank bug fixers, testers and your parents.
* COPYRIGHT or LICENSE copyright restrictions.
* AVAILABILITY Where to download from
* AUTHOR who made it.

The bold sections should be the minimum to Document. Other sections already exist in the repository or could not apply to this particular project.

### Pod markup summary

**This is a reduced set**, if anyone is interested on the full description, follow this reference: https://perldoc.perl.org/perlpod.html

```pod
=encoding utf8

=head1 NAME

There are 4 header level 1..4

Pod will indent each section,
as in many markup languages, two or more lines together are printed as a single line.

=head2

Always leave a blank line before and after each pod tag,
log lines can be split into consecutive lines.

Indent one level with a tab to document code and create a verbatim sections where each line is printed separately.

    sub myFunction {
        print "Something";
    }

```

Basic styles not all available in terminal
```pod
B<bold text>
I<Italic text, shown as underline text in terminal>
C<code text>
B<tags can be I<nested>>
```

**Example pod file in asbru-cm**

```
__END___
=encoding utf8

=head1 NAME

asbru-cm

=head1 SYNOPSYS

asbru-cm [options]

B<Options>

    --help : show this message
    --no-backup : do no create alternative config files as a backup (faster shutdown)
    --start-shell : start a local terminal
    --password=<pwd> : automatically logon with given password without prompting user
    --start-uuid=<uuid>[:<cluster] : start connection in cluster (if given)
    --edit-uuid=<uuid> : edit connection
    --dump-uuid=<uuid> : dump data for given connection
    --scripts : open scripts window
    --start-script=<script> : start given script
    --preferences : open global preferences dialog
    --quick-conn : open the Quick Connect dialog on startup
    --list-uuids : list existing connections/groups and their UUIDs
    --no-splash : no splash screen on startup
    --iconified : go to tray once started
    --readonly : start in read only mode (no config changes allowed)

=head1 DESCRIPTION

=head2 Global Variables

I<$CFG_DIR>    Setup your configuration directory here.

You may run different versions of Ásbru and each have different configuration settings and connections.

=head2 Functions

C<sub config_migration> (no parameters) (no return values)

Function normally empty unless there is a migration of the configuration files.

```

**See result executing** `perldoc asbru-cm`
