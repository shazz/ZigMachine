import numpy as np
from numpy import pi
import matplotlib.pyplot as plt
import struct
import os

WIDTH = 320
AMPLITUDE = 16
PERIODS = 2
DATA_SIZE = 2
FILE_PATH = "assets/scroll_sin.dat"

# 100 linearly spaced numbers
x = np.linspace(0, PERIODS*2*pi, WIDTH)


# the function, which is y = sin(x) here
y = (1.0 + np.sin(x))*AMPLITUDE/2

fig = plt.figure()
ax = fig.add_subplot(1, 1, 1)

ax.xaxis.set_ticks_position('bottom')
ax.yaxis.set_ticks_position('left')

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

assert os.path.getsize(FILE_PATH) == DATA_SIZE*WIDTH, f"Expected file size: {DATA_SIZE*WIDTH} not {os.path.getsize(FILE_PATH)}"

print(table_int)