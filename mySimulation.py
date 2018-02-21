#!/usr/bin/python
from TOSSIM import *
import sys, os
import random

total_nodes = 5 ** 2
total_time = 6000

t = Tossim([])
f = open('./logfile.txt', 'w');f.truncate()
#f = sys.stdout

SIM_END_TIME = total_time * t.ticksPerSecond()

print("TicksPerSecond : ", t.ticksPerSecond(), "\n")
# t.addChannel("RoutingMsg", f)
t.addChannel("Radio", f)
t.addChannel("SRTreeC", f)
t.addChannel("dbg", f)
t.addChannel("Readings", f)
t.addChannel("Boot", f)
t.addChannel("CH", f)
# t.addChannel("OUT",f)

for i in range(0, total_nodes):
    m = t.getNode(i)
    m.bootAtTime(10 * t.ticksPerSecond() + i)

topo = open("topology.txt", "r")

if topo is None:
    print
    "Topology file not opened!!! \n"

r = t.radio()
lines = topo.readlines()
for line in lines:
    s = line.split()
    if (len(s) > 0):
        print
        " ", s[0], " ", s[1], " ", s[2];
        r.add(int(s[0]), int(s[1]), float(s[2]))

mTosdir = os.getenv("TINYOS_ROOT_DIR")
noiseF = open(mTosdir + "/tos/lib/tossim/noise/meyer-heavy.txt", "r")
lines = noiseF.readlines()

for line in lines:
    str1 = line.strip()
    if str1:
        val = int(str1)
        for i in range(0, total_nodes):
            t.getNode(i).addNoiseTraceReading(val)

noiseF.close()

for i in range(0, total_nodes):
    t.getNode(i).createNoiseModel()

ok = False
h = True

while (h):
    try:
        h = t.runNextEvent()
        # print h
    except KeyboardInterrupt:
        print("Ctrl+C pressed!")
        exit(0)

    if (t.time() >= SIM_END_TIME):
        h = False
    if (h <= 0):
        ok = False

try:
    print("Node 0 connected with node 1", r.connected(0, 1), r.connected(1, 0))
    print("Node 0 connected with node 2", r.connected(0, 2), r.connected(2, 0))
    print("Node 1 connected with node 7", r.connected(1, 7), r.connected(7, 1))
    print("Node 2 connected with node 3", r.connected(2, 3), r.connected(3, 2))
    print("Node 4 connected with node 8", r.connected(4, 8), r.connected(8, 4))
except Exception as e:
    pass
