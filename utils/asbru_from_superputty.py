#!/usr/bin/python3
#Author: Brian Raaen
#Original code: https://www.brianraaen.com/2016/11/04/superputty-to-pac-manager/
#
#This script can convert a SuperPutty Sessions.xml file to an Asbru-cm yaml file. The
#resulting yaml file can then be imported into Asbru-cm.
#This script does require tweaking for your personal setup in the template section.
#For example, add the location of your personal ssh keys to "public key: /home/user".
#Similarly if you want to use a jump off box you can add it to the options section.
#options: ' -X -o "proxycommand=ssh -W %h:%p myhostname.com"'
#To create the Asbru-cm yaml file place your SuperPutty Sessions.xml file in the same
# directory as this script and run asbru_from_superputty.py >importfile.yml.


import uuid
import xml.etree.ElementTree as ET

def branchListImport(devices):
    temp = []
    branches = {}
    for y in devices:
        x = y['SessionId'].split('/')[:-1]
        if "/".join(y['SessionId'].split('/')[:-1]) not in branches:
            if x[0] not in branches:
                branches.update({str(x[0]) : {'name' : str(x[0]), 'description' : str(x[0]), 'uuidNumber' : uuid.uuid4(), 'parent' : "__PAC__EXPORTED__"}})
            if len(x) > 1:
                for y in range(1,len(x)):
                  if "/".join(x[:(y+1)]) not in branches:
                      branches.update({"/".join(x[:(y+1)]) : {'name': "/".join(x[:(y+1)]), 'description' : str(x[y]), 'uuidNumber' : uuid.uuid4(), 'parent' : str(branches["/".join(x[:y])]['uuidNumber'])}})
    for x in sorted(branches.items()):
        temp.append(branchPoint(**x[1]))
    for x in temp:
        for y in temp:
            if str(x.uuid) == str(y.parent):
                x.addChild(y.uuid)
    return temp


def deviceListImport(devices, branchList):
    temp = []
    for x in devices:
        temp.append(device(description=x['SessionName'], parentName="/".join(x['SessionId'].split('/')[:-1]), ip=x['Host'], port=x['Port'], method=x['Proto'], username=x['Username'] ))
    for x in temp:
        for y in branchList:
            if x.parentName == y.name:
                x.parentUuid = str(y.uuid)
                y.addChild(str(x.uuid))
                break
    return temp


class device(object):
    def __init__(self, description="", parentName="Unknown", parentUuid=False, uuidNumber=False, ip="", port="", method="", username="", password=False):
        self.description = description
        self.parentName = parentName
        self.parentUuid = parentUuid
        if uuidNumber == False:
            self.uuid = uuid.uuid4()
        else:
            if isinstance(uuidNumber, uuid.UUID):
                self.uuid = uuidNumber
            elif isinstance(uuidNumber, str):
                self.uuid = uuid.UUID(uuidNumber)
        self.ip = ip
        self.port = port
        if method.upper() == "SSH":
            self.method = "SSH"
        elif method.upper() == "TELNET":
            self.method = "Telnet"
        else:
            self.method = method.upper()
        self.username = username
        self.password = password
    def __hash__(self):
        return hash(self.description, self.parentName, self.parentUuid, self.uuid, self.ip, self.port, self.method, self.username, self.password)
    def __str__(self):
        return str(self.uuid)
    def __repr__(self):
        return 'asbru_template.device(description="{}", parentName={}, parentUuid="{}", uuidNumber="{}", ip="{}", port="{}", method="{}", username="{}", password="{}"'.format(self.description, self.parentName, self.parentUuid, self.uuid, self.ip, self.port, self.method, self.username, self.password)
    @property
    def ymlString(self):
        if self.password == False:
            password = "<<ASK_PASS>>"
        else:
            password = self.password
        return elementTemplate.format(uuid=self.uuid, ip=self.ip, desc=self.description, parent=self.parentUuid, port=self.port, method=self.method, username=self.username, password=password)


class branchPoint(object):
    def __init__(self, description="", name="", parent="__PAC__EXPORTED__", children=False,uuidNumber=False):
        self.description = description
        self.name = name
        self.parent = parent
        self.children = children
        if uuidNumber == False:
            self.uuid = uuid.uuid4()
        else:
            if isinstance(uuidNumber, uuid.UUID):
                self.uuid = uuidNumber
            elif isinstance(uuidNumber, str):
                self.uuid = uuid.UUID(uuidNumber)
    def __hash__(self):
        return hash(self.uuid, self.name, self.description, self.parent, self.children)
    def __str__(self):
        return str(self.uuid)
    def __repr__(self):
        return 'asbru_template.branchPoint(description="{}", name={}, parent="{}", children={}, uuidNumber="{}"'.format(self.description, self.name, self.parent, self.children, self.uuid)
    def addChild(self, child):
        if self.children == False:
            self.children = []
        self.children.append(str(child))
    @property
    def ymlString(self):
        temp = "{}:\n  _is_group: 1\n  _protected: 0\n  children:\n".format(str(self.uuid))
        if self.children != False:
            for x in self.children:
                temp += "    {}: 1\n".format(x)
        temp += "  cluster: []\n  description: Connection group '{0}'\n  name: {0}\n  parent: {1}\n  screenshots: ~\n  variables: []".format(self.description, self.parent)
        return temp

elementTemplate = """{uuid}:
  KPX title regexp: '.*{desc}.*'
  _is_group: 0
  _protected: 0
  auth fallback: 1
  auth type: userpass
  autoreconnect: ''
  autossh: ''
  children: {{}}
  cluster: []
  description: "Connection with '{desc}'"
  embed: 0
  expect: []
  favourite: 0
  infer from KPX where: 3
  infer user pass from KPX: ''
  ip: {ip}
  local after: []
  local before: []
  local connected: []
  mac: ''
  macros: []
  method: {method}
  name: '{desc}'
  options: ''
  parent: {parent}
  pass: '{password}'
  passphrase: ''
  passphrase user: ''
  port: {port}
  prepend command: ''
  proxy ip: ''
  proxy pass: ''
  proxy port: 8080
  proxy user: ''
  public key: /home/user
  quote command: ''
  remove control chars: ''
  save session logs: ''
  screenshots: ~
  search pass on KPX: 0
  send slow: 0
  socks5 tunnel active: ''
  send string active: ''
  send string every: 60
  send string only when idle: 0
  send string intro: 1
  send string txt: ''
  session log pattern: <UUID>_<NAME>_<DATE_Y><DATE_M><DATE_D>_<TIME_H><TIME_M><TIME_S>.txt
  session logs amount: 10
  session logs folder: ~/.config/pac/session_logs
  startup launch: ''
  startup script: ''
  startup script name: sample1.pl
  terminal options:
    audible bell: ''
    back color: '#000000000000'
    bold color: '#cc62cc62cc62'
    bold color like text: 1
    command prompt: '[#%\$>]|\:\/\s*$'
    cursor shape: block
    disable ALT key bindings: ''
    disable CTRL key bindings: ''
    disable SHIFT key bindings: ''
    open in tab: 1
    password prompt: "([pP]ass|[pP]ass[wW]or[dt]|ontrase.a|Enter passphrase for key \'.+\'):\\s*$"
    tab back color: '#000000000000'
    terminal backspace: auto
    terminal character encoding: UTF-8
    terminal emulation: xterm
    terminal font: Monospace 9
    terminal scrollback lines: 5000
    terminal select words: '-.:_/'
    terminal transparency: 0
    terminal window hsize: 800
    terminal window vsize: 600
    text color: '#cc62cc62cc62'
    timeout command: 40
    timeout connect: 40
    use personal settings: ''
    use tab back color: ''
    username prompt: '([l|L]ogin|[u|u]suario|[u|U]ser-?[n|N]ame|[u|U]ser):\s*$'
    visible bell: ''
  title: '{desc}'
  use prepend command: ''
  use proxy: 0
  use sudo: ''
  user: {username}
  variables: []"""

def main():
    temp = []
    tree = ET.parse('Sessions.xml')
    root = tree.getroot()
    devices = []
    for child in root:
        if child.tag == 'SessionData':
            devices.append(child.attrib)
    branchList = branchListImport(devices)
    deviceList = deviceListImport(devices, branchList)

    temp.append("---\n__PAC__EXPORTED__:\n  children:")
    temp += ["    {}: 1".format(str(x.uuid)) for x in branchList if '__PAC__EXPORTED__' == x.parent]
    temp += [x.ymlString for x in branchList]
    temp += [x.ymlString for x in deviceList]

    print("\n".join(temp))


if __name__ == "__main__":
  main()
