This article has been written by [Gaëtan Frenoy](https://github.com/gfrenoy)

# Using a Jump Host

## What is a Jump Host and why should I use it ?

By exposing all options and powerful features of [OpenSSH](https://www.openssh.com/), Ásbrú-CM is able to easily manage a large range of complex network configuration schemes using SSH tunnels[1].

With its new "Jump Host" feature, Ásbrú-CM makes it even easier for the most common case where you cannot reach your final destination because your client is not allowed to go trough a firewall or proxy.

![Client blocked by a firewall](images/jump-host-client-blocked.svg)

This is typically the case when that destination is located into a demilitarized zone (DMZ) of your network and can only be accessed by a few number of gateway hosts, also named "jump hosts".

In that case, you have to first connect to that jump host and, from there, connect to your final destination:

![Client using a jump host manually](images/jump-host-manual.svg)

This can perfectly be achieved by creating two SSH connections.  For the first one, you will create a local port forwarding to your final destination ; and for the second one, you'll target your local port instead of the final destination.

As of version 6.1, this becomes ever easier and you can set this up in a single connection by using the new "Jump host" option.

![Client using a SSH jump host with Ásbrú Connection Manager](images/jump-host-automatic.svg)

## How do I use a Jump Host with Ásbrú Connection Manager ?

In the ```Connection Details``` of your connection, specify the final destination host and how you want to connect to it:

<img src="/Managing/images/jump-host-connection-settings.png" alt="Connection Details" width="640"/>

In the ```Network Settings``` panel, specify the host name and how you want to connect to it:

<img src="/Managing/images/jump-host-network-settings.png" alt="Connection Network Settings" width="640"/>

In the above screenshots, we are assuming you are connecting to the final destination ```destination.example.org``` on port 22 using the default private key and user ```my-user``` through a jump host named ```jump.example.org``` on which we connect on port 22 and using the default private and user ```jump-user```.

## What does Ásbrú Connection Manager behind the scene ?

According to the final destination and your version of OpenSSH, Ásbrú-CM will either:
- Use the ```ProxyJump``` option of OpenSSH
- Use [netcat](http://man.openbsd.org/nc.1) and the ```ProxyCommand``` of OpenSSH
- Create a SSH tunnel and use port forwarding

All of these techniques are described in detail in [this cookbook for OpenSSH proxies and jump hosts](https://en.wikibooks.org/wiki/OpenSSH%2FCookbook%2FProxies_and_Jump_Hosts).

## Limitations

- Jump Host can only be used for the following connection types : SSH, RDP, VNC.
- Multiple jump hosts are not supported.

## More references

[1] There are plenty of articles on that topics, here is a short selection:

 - [SSH tunnelling explained](https://chamibuddhika.wordpress.com/2012/03/21/ssh-tunnelling-explained/)
 - [Can someone explain SSH tunnel in a simply way](https://stackoverflow.com/questions/5280827/can-someone-explain-ssh-tunnel-in-a-simple-way)
 - [How does SSH work](https://www.hostinger.com/tutorials/ssh-tutorial-how-does-ssh-work)
