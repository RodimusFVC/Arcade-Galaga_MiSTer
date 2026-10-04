# Verilog 8085 Microprocessor Implementation

This project is a complete Verilog HDL implementation of the Intel 8085 8-bit microprocessor. It is designed for educational purposes and supports a range of instructions covering data transfer, arithmetic, logic, and branching operations.

Built to simulate instruction-level execution, this design is modular and can be tested using Verilog simulation tools.



## Features Implemented

- Instruction fetch, decode, and execute stages
- Arithmetic and Logic Unit (ALU)
- General-purpose register file (registers A, B, C, D, E, H, L)
- Memory read/write support
- Branching and jump control logic
- Instruction decoder with support for register, immediate, and memory addressing
- Halt (HLT) instruction for stopping execution

---

## Supported Instructions 

Category: Data Transfer  
- MOV, MVI, LDA, STA

Category: Arithmetic  
- ADD, ADC, SUB, SBB, INR, DCR

Category: Logical  
- ANA, XRA, ORA, CMP

Category: Branching  
- JMP, JZ, JNZ, JC, JNC, JP, JM, JPE, JPO

Category: Miscellaneous  
- HLT

---
## File Structure
├── src files/

│ ├── IDecoder.v - Instruction decoder module

│ ├── ALU.v - Arithmetic and Logic Unit

│ ├── RegisterFile.v - General-purpose registers

│ ├── ControlUnit.v - Instruction control logic (FSM)

│ ├── MP85.v - Top-level processor module

│ └── Memory.v - Program and data memory

├── testbenches/

│ └── tb_MP85.v - Testbench for top-level processor

## Limitations

This implementation mimics the Intel 8085 microprocessor but with a few limitations:

- Interrupts are not currently supported.
- The number of clock cycles for some instructions may differ slightly from the original 8085 processor.

---

## License

Copyright 2025 Swarup Saha Roy

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.


## Contributing

Contributions are welcome. You can extend instruction support, refactor modules, or port this design to an FPGA platform.

---

## Author

Developed by: Swarup Saha Roy

Contact: swarupsaharoy2004@gmail.com 

Institution: Jadavpur University








