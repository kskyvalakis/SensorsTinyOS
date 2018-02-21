"""
Python script to generate topology.txt file.
"""

from math import sqrt as sqrt
import sys


def find_neighbors(m, i, j, r, d):
    neighbor = []
    for x in range(0, d):
        for y in range(0, d):
            if x != i or y != j:
                dist = sqrt((i - x) * (i - x) + (j - y) * (j - y))
                if dist <= r:
                    neighbor.append(m[x][y])

    return neighbor


def main():
    try:
        D = int(sys.argv[1])
        r = float(sys.argv[2])
    except Exception:
        D = 3
        r = 1

    # Grid generation
    M = list(range(D * D))
    M = [M[i:i + D] for i in range(0, len(M), D)]

    # Find neighbors of each node and write them to a topology.txt file
    file = open('topology.txt', 'w')
    file.truncate()
    for i in range(0, D):
        for j in range(0, D):
            neighbors = find_neighbors(M, i, j, r, D)
            print(neighbors)
            for k in range(0, len(neighbors)):
                file.write("%s %s %s\n" % (M[i][j], neighbors[k], -50))
        file.write('\n')

    file.close()


if __name__ == '__main__':
    main()
