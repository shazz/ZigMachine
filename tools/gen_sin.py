import numpy as np
from numpy import pi
import matplotlib.pyplot as plt
import struct
import os
from dotmap import DotMap

ancool_params = {
    "nb_points" :  640*2,
    "amplitude" :  40,
    "periods" :  2,
    "data_size" :  2,
    "file_path" :  "src/assets/screens/ancool/scroller_sin.dat",
    "start" :  -1.2,
    "y_offset" :  0,
    "range" :   640*2,
    "offset" :  2*pi/640*2,
}

ics_params = {
    "nb_points" :  640*2,
    "amplitude" :  20,
    "periods" :  1,
    "data_size" :  2,
    "file_path" :  "src/assets/screens/ics/scroller_sin.dat",
    "start" :  0,
    "y_offset" :  20,
    "range" :   640*2,
    "offset" :  2*pi/640,
}
params = DotMap(ics_params)


# linearly spaced numbers
x = np.linspace(0, params.range, params.nb_points)
print(x, len(x))

# the function, which is y = sin(x) here
# y = (1.0 + np.sin(x*OFFSET))*AMPLITUDE/2
y = np.sin((x + params.start) * params.offset) * params.amplitude + params.y_offset

fig = plt.figure()
ax = fig.add_subplot(1, 1, 1)

ax.xaxis.set_ticks_position('bottom')
ax.yaxis.set_ticks_position('left')
plt.ylim(-200, 200)
plt.xlim(0, params.range)

# plot the function
plt.plot(x, y, 'b-')

# show the plot
plt.show()

table_int = [int(i) for i in y]

if params.data_size == 2:
    table_bytes = struct.pack("{}h".format(len(table_int)), *table_int)
elif params.data_size == 1:
    table_bytes = struct.pack("{}B".format(len(table_int)), *table_int)
else:
    raise RuntimeError("umanaged size, check: https://docs.python.org/3/library/struct.html#format-characters")

with open(params.file_path, "wb") as f:
    f.write(table_bytes)

assert os.path.getsize(params.file_path) == params.data_size * params.nb_points, f"expected file size: {params.data_size * params.nb_points} not {os.path.getsize(params.file_path)}"

print(table_int)