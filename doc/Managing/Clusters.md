This article has been written by [Hans Peyrot](https://github.com/hanspr)

# Why do you need a cluster ?

This is more an admin tool than programmers, you can use it to type common commands to servers that are identical or at least very similar, this allows you to:

* update several servers
* edit a config file on all of them at the same time

__From a programmer point of view__

As an example, I program remote Raspeberri Pi that are connected to electronic scales, etc. And have a very unique code that is similar across them, but I do not have a development environment because I do not have the interest in buying expensive scales or robot arms, to be able to develop. So I connect to all of them simultaneously, they all have exactly the same code; then I edit the code on one terminal and I'm patching on real time the others. Of course I could work on one and then copy the file to the others, but for small adjustments this has been always more practical.

And there are some other more complicated uses when add to the terminals tunnels, expect, etc. All those tunnels will open simultaneously too.

# Create a cluster

In ```Clusters```, click on the ```Add``` button a provide the name of your new cluster:

![imagen](https://user-images.githubusercontent.com/1572396/67621669-81d8a900-f7d7-11e9-9587-140c838d9f0f.png)

Select the connections from the left list and add them to the cluster using button ```Add to cluster```:

![imagen](https://user-images.githubusercontent.com/1572396/67621672-8ac97a80-f7d7-11e9-9508-3fbdcbf6df83.png)

When done selecting, click the ```OK``` button to save your changes:

![imagen](https://user-images.githubusercontent.com/1572396/67621678-a2086800-f7d7-11e9-996a-39692b22c9fc.png)

The new cluster will be available in the menu or the cluster list on the main window.

![imagen](https://user-images.githubusercontent.com/1572396/67621680-b5b3ce80-f7d7-11e9-85c3-54b9726d5447.png)

# Using an existing cluster

Either from the system bar menu or from the ```Clusters``` menu in the left side bar of Ásbrú Connection Manager, run your cluster:

![imagen](https://user-images.githubusercontent.com/1572396/67621685-c5cbae00-f7d7-11e9-8946-010a863ccf57.png)

This will open all terminals **simultaneously** and link the keyboard to ***all terminals*** in the cluster.
So anything you write on one will be simultaneously typed in the others.

![imagen](https://user-images.githubusercontent.com/1572396/67621699-fa3f6a00-f7d7-11e9-8bca-1cdde9285516.png)

# Power Cluster Management

The Power Cluster Management (aka PCC), is used on 2 conditions:

* You open several terminals that have no cluster
  * So you open the PCC and activate, send keys to all open terminals, similar, but terminals are not clustered
  * Open a cluster and for some reason you loose communication with one of them and that terminal reconnects but is no longer with the cluster.
* Its main advantage is that you can type a command on a single terminal and is not passed to the others, you use the PCC to pass it to all. With a cluster you can not type a different command on one of them they are tied together.
