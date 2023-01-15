import numpy as np
from numpy import pi
import matplotlib.pyplot as plt
import struct
import os

NB_POINTS = 640*2
AMPLITUDE = 40
PERIODS = 2
DATA_SIZE = 2
FILE_PATH = "src/assets/screens/ancool/scroller_sin.dat"
START = -1.2
Y_OFFSET = 0
RANGE = NB_POINTS
OFFSET = 2*pi/RANGE

# linearly spaced numbers
x = np.linspace(0, RANGE, NB_POINTS)
print(x, len(x))

# the function, which is y = sin(x) here
# y = (1.0 + np.sin(x*OFFSET))*AMPLITUDE/2
y = np.sin((x+START)*OFFSET)*AMPLITUDE + Y_OFFSET

fig = plt.figure()
ax = fig.add_subplot(1, 1, 1)

ax.xaxis.set_ticks_position('bottom')
ax.yaxis.set_ticks_position('left')
plt.ylim(-200, 200)
plt.xlim(0, RANGE)

# plot the function
plt.plot(x, y, 'b-')

# show the plot
plt.show()

table_int = [int(i) for i in y]

if DATA_SIZE == 2:
    table_bytes = struct.pack("{}h".format(len(table_int)), *table_int)
elif DATA_SIZE == 1:
    table_bytes = struct.pack("{}B".format(len(table_int)), *table_int)
else:
    raise RuntimeError("umanaged size, check: https://docs.python.org/3/library/struct.html#format-characters")

with open(FILE_PATH, "wb") as f:
    f.write(table_bytes)

assert os.path.getsize(FILE_PATH) == DATA_SIZE*NB_POINTS, f"Expected file size: {DATA_SIZE*NB_POINTS} not {os.path.getsize(FILE_PATH)}"

print(table_int)