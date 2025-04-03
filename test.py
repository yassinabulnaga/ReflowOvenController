import time
import sys
import serial
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from matplotlib.patches import Circle, Rectangle
from matplotlib import cm
import matplotlib.gridspec as gridspec

# --------------------------------------------------
# Configure Serial Port
# --------------------------------------------------
ser = serial.Serial(
    port='COM3',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS,
    timeout=1.0
)
ser.isOpen()
print("Connected to:", ser.name)

# --------------------------------------------------
# Global Parameters for Temperature Plot and FSM
# --------------------------------------------------
xsize = 100
window_size = 10  # for moving average calculation
paused = False    # pause flag

# FSM (Finite State Machine) parameters
current_fsm_state = 0  # starting state: RESTING
state_start_time = time.time()
state_durations = {
    1: 60,  # ramp to soak
    2: 60,  # soak
    3: 60,  # ramp to reflow
    4: 60,  # reflow
    5: 30,  # cool down
}
state_names = {
    0: "RESTING",
    1: "RAMP TO SOAK",
    2: "SOAK",
    3: "RAMP TO REFLOW",
    4: "REFLOW",
    5: "COOL DOWN",
    6: "ERROR",
    7: "DONE"
}

# Total duration (sum of all states, excluding RESTING)
total_duration = sum(state_durations.values())

# Data lists for the temperature plot
xdata, ydata, y_moving_avg = [], [], []
get_temps_t = -1  # time counter for temperature readings

# Process-start flag; remains False until the circuit sends a "BUTTON" message.
process_started = False

# --------------------------------------------------
# Bouncing Ball Parameters
# --------------------------------------------------
ball_area_height = 150  # larger vertical boundary for ball area
ball_radius = 1         # even smaller ball for a more elaborate maze
xball = xsize / 2       # horizontal center
yball = ball_area_height / 2  # vertical center
xball_velocity = 0.4    # initial horizontal velocity
yball_velocity = 0.4    # initial vertical velocity

# Maze obstacles inside the ball area (now removed from drawing)
vertical_obstacles = [
    {'x': 50, 'ymin': 30, 'ymax': 120},
    {'x': 30, 'ymin': 60, 'ymax': 140}
]
horizontal_obstacles = [
    {'y': 75, 'xmin': 20, 'xmax': 80}
]

# --------------------------------------------------
# Helper & Callback Functions
# --------------------------------------------------
def toggle_pause(event):
    global paused
    if event.key == ' ':
        paused = not paused

def get_temps():
    """Generator that reads temperature values from serial.
       If the serial line equals b'BUTTON', the process is started.
    """
    global get_temps_t, process_started
    while True:
        if not paused:
            get_temps_t += 1
            line_in = ser.readline().strip()
            print(line_in)
            # Check for button press signal from the circuit.
            if line_in == b"BUTTON":
                process_started = True
                continue  # Do not yield a temperature reading
            try:
                temp_val = float(line_in)
            except ValueError:
                temp_val = 0.0
            yield get_temps_t, temp_val
        time.sleep(0.05)

def moving_average(data, window_size):
    if len(data) < window_size:
        return np.mean(data) if data else 0
    return np.mean(data[-window_size:])

def interpolate_bg_color(temp):
    """
    Returns an RGB tuple for a background color that transitions
    from light blue (cool) to red (hot) as temperature increases.
    """
    t = np.clip(temp / 80.0, 0.0, 1.0)
    r0, g0, b0 = 0.6, 0.8, 1.0
    r1, g1, b1 = 1.0, 0.4, 0.4
    r = r0 + (r1 - r0) * t
    g = g0 + (g1 - g0) * t
    b = b0 + (b1 - b0) * t
    return (r, g, b)

def update_ball(temp):
    """
    Update the ball's position and velocity based on the current temperature.
    A higher temperature increases the ball's speed.
    Also handles collisions with the maze obstacles.
    """
    global xball, yball, xball_velocity, yball_velocity, ball_radius, xsize, ball_area_height

    speed_factor = np.clip(temp / 20, 0.1, 5.0)
    vx_sign = np.sign(xball_velocity) if xball_velocity != 0 else 1
    vy_sign = np.sign(yball_velocity) if yball_velocity != 0 else 1
    xball_velocity = vx_sign * speed_factor
    yball_velocity = vy_sign * speed_factor

    xball += xball_velocity
    yball += yball_velocity

    # Bounce off outer boundaries
    if xball - ball_radius < 0 or xball + ball_radius > xsize:
        xball_velocity = -xball_velocity
    if yball - ball_radius < 0 or yball + ball_radius > ball_area_height:
        yball_velocity = -yball_velocity

    xball = np.clip(xball, ball_radius, xsize - ball_radius)
    yball = np.clip(yball, ball_radius, ball_area_height - ball_radius)

    # Bounce off vertical obstacles (collision logic remains, even though they are not drawn)
    for obs in vertical_obstacles:
        if obs['ymin'] <= yball <= obs['ymax'] and abs(xball - obs['x']) < ball_radius:
            xball_velocity = -xball_velocity
            if xball < obs['x']:
                xball = obs['x'] - ball_radius
            else:
                xball = obs['x'] + ball_radius

    # Bounce off horizontal obstacles (collision logic remains, even though they are not drawn)
    for obs in horizontal_obstacles:
        if obs['xmin'] <= xball <= obs['xmax'] and abs(yball - obs['y']) < ball_radius:
            yball_velocity = -yball_velocity
            if yball < obs['y']:
                yball = obs['y'] - ball_radius
            else:
                yball = obs['y'] + ball_radius

    # Update the ball's position on the plot
    circle.set_center((xball, yball))

def run(data):
    """
    Main update function called by the animation. It performs these tasks:
      1. Updates the temperature plot (with a moving average).
      2. Updates two progress bars: one for overall process and one for the current state.
         (Both remain at 0% until the process is started.)
      3. Updates the bouncing ball’s position, color, and the background of its area.
    """
    global current_fsm_state, state_start_time, process_started

    t, temp = data

    # 1. Temperature Plot Update
    xdata.append(t)
    ydata.append(temp)
    avg_y = moving_average(ydata, window_size)
    y_moving_avg.append(avg_y)
    if t > xsize:
        ax_temp.set_xlim(t - xsize, t)
    line.set_data(xdata, ydata)
    line_avg.set_data(xdata, y_moving_avg)
    # Keep the y-axis fixed from 15 to 250 degrees
    ax_temp.set_ylim(15, 250)

    # 2. FSM & Progress Bars Update
    if current_fsm_state == 0:
        # In RESTING state, both progress bars remain at 0%
        overall_prog = 0
        state_prog = 0
        # Only start the process when the circuit sends "BUTTON"
        if process_started:
            current_fsm_state = 1
            state_start_time = time.time()
    else:
        # Update the current state's progress
        elapsed = time.time() - state_start_time
        duration = state_durations.get(current_fsm_state, 60)
        state_prog = min(100, (elapsed / duration) * 100)
        # Transition to the next state if the current state's duration has elapsed
        if elapsed >= duration and current_fsm_state in state_durations:
            if current_fsm_state < 5:
                current_fsm_state += 1
                state_start_time = time.time()
            else:
                current_fsm_state = 7  # DONE

        # Compute overall progress (sum the durations of completed states plus the current state's elapsed time)
        if current_fsm_state == 7:
            overall_elapsed = total_duration
        else:
            completed_time = sum(state_durations[s] for s in range(1, current_fsm_state))
            overall_elapsed = completed_time + (time.time() - state_start_time if current_fsm_state in state_durations else 0)
        overall_prog = min(100, (overall_elapsed / total_duration) * 100)

    overall_bar.set_width(overall_prog)
    overall_text.set_text(f"Total Process: {overall_prog:.0f}%")
    state_bar.set_width(state_prog)
    state_text.set_text(f"{state_names[current_fsm_state]}: {state_prog:.0f}%")

    # 3. Bouncing Ball Update
    update_ball(temp)
    norm_temp = np.clip(temp, 0, 80) / 80.0
    circle_color = cm.jet(norm_temp)
    circle.set_color(circle_color[:3])
    bg_color_ball = interpolate_bg_color(temp)
    ax_ball.set_facecolor(bg_color_ball)

    return line, line_avg, overall_bar, overall_text, state_bar, state_text, circle

def on_close_figure(event):
    print("Closing figure and serial port...")
    ser.close()
    sys.exit(0)

# --------------------------------------------------
# Create Figure with GridSpec Layout
# --------------------------------------------------
fig = plt.figure(figsize=(12, 6))
fig.canvas.mpl_connect('close_event', on_close_figure)
fig.canvas.mpl_connect('key_press_event', toggle_pause)

# Use a 3-row by 2-column GridSpec.
# Left column: row 0 for temperature plot, row 1 for overall progress, row 2 for state progress.
# Right column (all rows): bouncing ball area.
gs = gridspec.GridSpec(3, 2, width_ratios=[3, 1], height_ratios=[8, 1, 1])

# Temperature Plot (Top Left)
ax_temp = fig.add_subplot(gs[0, 0])
line, = ax_temp.plot([], [], lw=2, label='Temperature')
line_avg, = ax_temp.plot([], [], lw=2, color='orange', label='Moving Average')
ax_temp.set_xlim(0, xsize)
# Set fixed y-axis limits from 15 to 250 degrees.
ax_temp.set_ylim(15, 250)
ax_temp.set_title("Temperature Data")
ax_temp.set_xlabel("Readings")
ax_temp.set_ylabel("Temperature (°C)")
ax_temp.grid(True)
ax_temp.legend()

# Overall Progress Bar (Middle Left)
ax_overall = fig.add_subplot(gs[1, 0])
ax_overall.set_xlim(0, 100)
ax_overall.set_ylim(-0.3, 0.3)
ax_overall.axis('off')
ax_overall.set_title("Overall Progress")
overall_bar = plt.Rectangle((0, 0.05), 0, 0.2,
                             facecolor='green', edgecolor='black', lw=2)
ax_overall.add_patch(overall_bar)
overall_text = ax_overall.text(50, -0.15, "",
                               ha='center', va='center', color='black', fontsize=12)

# State Progress Bar (Bottom Left)
ax_state = fig.add_subplot(gs[2, 0])
ax_state.set_xlim(0, 100)
ax_state.set_ylim(-0.3, 0.3)
ax_state.axis('off')
ax_state.set_title("State Progress")
state_bar = plt.Rectangle((0, 0.05), 0, 0.2,
                           facecolor='red', edgecolor='black', lw=2)
ax_state.add_patch(state_bar)
state_text = ax_state.text(50, -0.15, "",
                           ha='center', va='center', color='black', fontsize=12)

# Bouncing Ball Area (Right Column, spanning all rows)
ax_ball = fig.add_subplot(gs[:, 1])
ax_ball.set_xlim(0, xsize)
ax_ball.set_ylim(0, ball_area_height)
ax_ball.set_aspect('equal')
ax_ball.axis('off')
# Do not add a title for the ball plot
border = Rectangle((0, 0), xsize, ball_area_height, fill=False, edgecolor='black', lw=2)
ax_ball.add_patch(border)
circle = Circle((xball, yball), ball_radius, color='red')
ax_ball.add_patch(circle)
# Removed drawing of maze obstacles:
# for obs in vertical_obstacles:
#     ax_ball.plot([obs['x'], obs['x']], [obs['ymin'], obs['ymax']], color='black', lw=2)
# for obs in horizontal_obstacles:
#     ax_ball.plot([obs['xmin'], obs['xmax']], [obs['y'], obs['y']], color='black', lw=2)

# --------------------------------------------------
# Start the Animation
# --------------------------------------------------
get_temps.t = -1  # initialize time counter
ani = animation.FuncAnimation(fig, run, get_temps, blit=False, interval=100, repeat=False)
plt.tight_layout()
plt.show()
