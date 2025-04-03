# Reflow Oven Controller — ELEC291/ELEC292 Project
A precision reflow oven controller designed and implemented for the N76E003 microcontroller, programmed entirely in assembly. This system automates the reflow soldering process using a K-type thermocouple for real-time temperature monitoring, an OP07 op-amp for signal conditioning, and solid-state relay (SSR) control to regulate a standard toaster oven. The system includes a user-friendly LCD interface, password protection, data logging, and a Python-based visualization dashboard.


## ✨Features:
- Assembly-only firmware on the N76E003 microcontroller
- Real-time temperature monitoring with ±3°C accuracy using a calibrated K-type thermocouple
- Custom reflow profiles configurable via onboard pushbuttons
- Finite State Machine (FSM) governs process stages: Preheat, Soak, Reflow, Cool Down, Done, and Error
- LCD Interface shows current temperature, process time, and system state
- Secure Access with passcode entry before system use
- Live serial output for temperature data logging and strip chart plotting via Python
- Automated oven door opens using a DC motor at the end of the cycle
- Audio feedback with Super Mario theme music on completion
- Custom LCD icons (flame & snowflake) to indicate heating/cooling states

## 🧠 System Overview: 

This project is a fully functional reflow oven controller, designed using the N76E003 microcontroller and developed entirely in assembly language. It monitors and regulates oven temperature using a K-type thermocouple and controls a toaster oven through a solid-state relay. The controller features a user-friendly interface with an LCD display, secure passcode access, and live data logging through a Python-based serial interface.

<img width="1450" alt="image" src="https://github.com/user-attachments/assets/1e715722-19a4-454c-bb93-06489d2ab98f" />

Figure 1: Block diagram showing the integration between hardware and software components.



## 🔌 Hardware Overview

The hardware consists of temperature sensing, control, display, and user input subsystems. A K-type thermocouple is connected through an OP07 op-amp to the N76E003’s ADC input. An LCD and pushbutton interface enable user control, and the SSR regulates power to the oven.

<div align="center">
  <img width="727" alt="ELEC 291 Project1 LDC Push Buttons Circuit" src="https://github.com/user-attachments/assets/c5d91ec1-e180-455e-8f39-74904d435ef2" />
  <p><em>Figure 2: Circuit diagram of the LCD pushbuttons.</em></p>

  <img width="487" alt="ELEC 291 Project1 Op-Amp Circuit" src="https://github.com/user-attachments/assets/45478e6d-a702-4bf3-b6b0-c5189c249926" />
  <p><em>Figure 3: Circuit diagram of the op-amp circuit.</em></p>
</div>

## 💾 Software Architecture 

The firmware was written in assembly for the N76E003. A finite state machine (FSM) governs the reflow process stages: Rest, Ramp to Soak, Soak, Ramp to Reflow, Reflow, Cool Down, Done, and Error. Additional logic handles user input, password verification, and LCD updates.

<div align="center">
  <img width ='600' alt="ELEC 291 Project1 FSM V1" src="https://github.com/user-attachments/assets/15feddde-7cc8-48b1-b33e-bf499a3ad9d0" />
  <p><em>Figure 4: FSM state diagram for the reflow process.</em></p>
</div>

## 🔐 Extra Features






## 🙌 Team Members

This project was developed by **Group A13** as part of the **ELEC291/ELEC292** course at the University of British Columbia. Each member contributed equally to the design, coding, testing, and documentation phases.

| Team Member       |
|-------------------|
| Yassin Abulnaga   |
| Faris Alshouani   |
| Ali Danesh        |
| Ronald Feng       |
| Drédyn Fontana    |
| Nick Unruh        |







