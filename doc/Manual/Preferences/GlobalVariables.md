# Prferences : Global Variables

![](images/gv1.png)

Global variables, allow you to define variable name and a value assigned to that variable. That variable can be later used in any:

+ Local Command
+ Global Command
+ Expect definition

To add a new entry click on the "Add" Button.

+ __Variable__ : The name you want to assign to you variable.
+ __Value__ : The value of your variable. It can be any text.
+ __Hide__ : If this entry should be masked with the password character so its not visible displayed when editing this section.
+ __Delete__ button : Remove the selected variable from the list.

To use a variable use the pattern : <GV:variable_name>

For example, using the above image, you could create a command similar to this one:

`ls -l <GV:MyDocs>`

And assign it o a local, remote command or expect.


