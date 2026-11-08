/* One 6502 instruction: libcRSID's cRSID_emulateCPU() (CPU.c, RealSID mode) on sw_emulate_c64()'s locals
 * (kestrel_sw_cpu.c), in upstream's order and grouping so the two read side by side; leaves the cycles in ic,
 * or 0xFE (RTI out of the call) / 0xFF (RTS out of it). */
{
    unsigned int PrevPC = PC;
    IR = RD(PC); Cycles = 2; SamePage = 0;

    if (IR & 1) {                                    /* 1/5/9/D: accumulator; 3/7/B/F: illegal opcodes */
        switch ((IR & 0x1F) >> 1) {
        case 0: case 1: mXInd(); break;
        case 2: case 3: mZp(); break;
        case 4: case 5: mImm(); break;
        case 6: case 7: mAbs(); break;
        case 8: case 9: mIndY(); break;
        case 0xA: mZpX(); break;
        case 0xB: if ((IR & 0xC0) != 0x80) mZpX(); else mZpY(); break;
        case 0xC: case 0xD: mAbsY(); break;
        case 0xE: mAbsX(); break;
        case 0xF: if ((IR & 0xC0) != 0x80) mAbsX(); else mAbsY(); break;
        }
        Addr &= 0xFFFF;
        switch ((IR & 0xE0) >> 5) {
        case 0: if (MOSTLY((IR & 0x1F) != 0xB)) {   /* ORA / SLO */
                    if (RARELY((IR & 3) == 3)) { clrNZC(); setC(RD(Addr) >= N); WR(Addr, RD(Addr) << 1); Cycles += 2; }
                    else Cycles -= SamePage;
                    A |= RD(Addr); setNZbyA();
                } else { A &= RD(Addr); setNZbyA(); setC(A >= N); }  /* ANC */
                break;
        case 1: if (MOSTLY((IR & 0x1F) != 0xB)) {   /* AND / RLA */
                    if (RARELY((IR & 3) == 3)) { T = (RD(Addr) << 1) + (ST & C); clrNZC(); setC(T > 255); T &= 0xFF; WR(Addr, T); Cycles += 2; }
                    else Cycles -= SamePage;
                    A &= RD(Addr); setNZbyA();
                } else { A &= RD(Addr); setNZbyA(); setC(A >= N); }  /* ANC */
                break;
        case 2: if (MOSTLY((IR & 0x1F) != 0xB)) {   /* EOR / SRE */
                    if (RARELY((IR & 3) == 3)) { clrNZC(); setC(RD(Addr) & 1); WR(Addr, RD(Addr) >> 1); Cycles += 2; }
                    else Cycles -= SamePage;
                    A ^= RD(Addr); setNZbyA();
                } else { A &= RD(Addr); setC(A & 1); A >>= 1; A &= 0xFF; setNZbyA(); }  /* ALR */
                break;
        case 3: if (MOSTLY((IR & 0x1F) != 0xB)) {   /* ADC / RRA */
                    if (RARELY((IR & 3) == 3)) { T = (RD(Addr) >> 1) + ((ST & C) << 7); clrNZC(); setC(T & 1); WR(Addr, T); Cycles += 2; }
                    else Cycles -= SamePage;
                    T = A; A += RD(Addr) + (ST & C);
                    if (RARELY((ST & D) && (A & 0xF) > 9)) { A += 0x10; A &= 0xF0; }  /* upstream's BCD */
                    setNZCbyAdd(); setVbyAdd(RD(Addr), T);
#ifdef SW_CPU_BREAK
                    if (A == 0x80) ST ^= C;          /* the cpu check's --break: a wrong carry */
#endif
                } else {                             /* ARR */
                    A &= RD(Addr);
                    T = A; A = (A >> 1) + ((ST & C) << 7); setC(T >= N); setNZbyA();
                    ST &= ~V; ST |= (T & V) ^ (A & V);
                }
                break;
        case 4: if (RARELY((IR & 0x1F) == 0xB)) { A = X & RD(Addr); setNZbyA(); }  /* XAA */
                else if (RARELY((IR & 0x1F) == 0x1B)) { SP = A & X; WR(Addr, SP & ((Addr >> 8) + 1)); }  /* TAS */
                else { WR2(Addr, A & (RARELY((IR & 3) == 3) ? X : 0xFF)); }  /* STA / SAX */
                break;
        case 5: if (MOSTLY((IR & 0x1F) != 0x1B)) { A = RD(Addr); if (RARELY((IR & 3) == 3)) X = A; }  /* LDA / LAX */
                else { A = X = SP = RD(Addr) & SP; }  /* LAS */
                setNZbyA(); Cycles -= SamePage;
                break;
        case 6: if (MOSTLY((IR & 0x1F) != 0xB)) {   /* CMP / DCP */
                    if (RARELY((IR & 3) == 3)) { WR(Addr, RD(Addr) - 1); Cycles += 2; }
                    else Cycles -= SamePage;
                    T = A - RD(Addr);
                } else { X = T = (A & X) - RD(Addr); X &= 0xFF; }  /* SBX */
                setNZCbySub(T);
                break;
        case 7: if (RARELY((IR & 3) == 3 && (IR & 0x1F) != 0xB)) { WR(Addr, RD(Addr) + 1); Cycles += 2; }  /* ISC */
                else Cycles -= SamePage;
                T = A; A -= RD(Addr) + !(ST & C);    /* SBC */
                setNZCbySub(A); A &= 0xFF; setVbyAdd(~RD(Addr), T);
                break;
        }
    }

    else if (IR & 2) {                               /* 2: illegal/LDX, 6: A/X/INC/DEC, A: shifts/transfers/NOP, E */
        switch (IR & 0x1F) {
        case 2: mImm(); break;
        case 6: mZp(); break;
        case 0xE: mAbs(); break;
        case 0x16: if ((IR & 0xC0) != 0x80) mZpX(); else mZpY(); break;
        case 0x1E: if ((IR & 0xC0) != 0x80) mAbsX(); else mAbsY(); break;
        }
        Addr &= 0xFFFF;
        switch ((IR & 0xE0) >> 5) {
        case 0: clrC();                              /* ASL: then as ROL */
                __attribute__((fallthrough));
        case 1: if (CALMLY((IR & 0xF) == 0xA)) { A = (A << 1) + (ST & C); setNZCbyAdd(); }
                else { T = (RD(Addr) << 1) + (ST & C); setC(T > 255); setNZbyT(T); WR(Addr, T); Cycles += 2; }
                break;
        case 2: clrC();                              /* LSR: then as ROR */
                __attribute__((fallthrough));
        case 3: if (CALMLY((IR & 0xF) == 0xA)) { T = A; A = (A >> 1) + ((ST & C) << 7); setC(T & 1); A &= 0xFF; setNZbyA(); }
                else { T = (RD(Addr) >> 1) + ((ST & C) << 7); setC(RD(Addr) & 1); setNZbyT(T); WR(Addr, T); Cycles += 2; }
                break;
        case 4: if (MOSTLY(IR & 4)) { WR2(Addr, X); }  /* STX */
                else if (RARELY(IR & 0x10)) SP = X;   /* TXS */
                else { A = X; setNZbyA(); }           /* TXA */
                break;
        case 5: if (MOSTLY((IR & 0xF) != 0xA)) { X = RD(Addr); Cycles -= SamePage; }  /* LDX */
                else if (RARELY(IR & 0x10)) X = SP;  /* TSX */
                else X = A;                          /* TAX */
                setNZbyX();
                break;
        case 6: if (TIGHTLY(IR & 4)) { WR(Addr, RD(Addr) - 1); setNZbyM(); Cycles += 2; }  /* DEC */
                else { --X; setNZbyX(); }            /* DEX */
                break;
        case 7: if (TIGHTLY(IR & 4)) { WR(Addr, RD(Addr) + 1); setNZbyM(); Cycles += 2; }  /* INC / NOP */
                break;
        }
    }

    else if ((IR & 0xC) == 8) {                      /* 8: register / status flag */
        if (IR & 0x10) {
            if (IR == 0x98) { A = Y; setNZbyA(); }   /* TYA */
            else if (sw_flag_switches[IR >> 5] & 0x20) ST |= (sw_flag_switches[IR >> 5] & 0xDF);  /* SEC/SEI/SED */
            else ST &= ~(sw_flag_switches[IR >> 5] & 0xDF);  /* CLC/CLI/CLV/CLD */
        } else {
            switch ((IR & 0xF0) >> 5) {
            case 0: push(ST); Cycles = 3; break;     /* PHP */
            case 1: ST = pop(); Cycles = 4; break;   /* PLP */
            case 2: push(A); Cycles = 3; break;      /* PHA */
            case 3: A = pop(); setNZbyA(); Cycles = 4; break;  /* PLA */
            case 4: --Y; setNZbyY(); break;          /* DEY */
            case 5: Y = A; setNZbyY(); break;        /* TAY */
            case 6: ++Y; setNZbyY(); break;          /* INY */
            case 7: ++X; setNZbyX(); break;          /* INX */
            }
        }
    }

    else if ((IR & 0x1F) == 0x10) {                  /* the relative branches (no page-cross cycle, as upstream) */
        ++PC;
        T = RD(PC); if (T & 0x80) T -= 0x100;
        if (IR & 0x20) { if (ST & sw_branch_flags[IR >> 6]) { PC += T; Cycles = 3; } }
        else if (!(ST & sw_branch_flags[IR >> 6])) { PC += T; Cycles = 3; }
    }

    else {                                           /* 0/4/C: control, Y, compares, JMP */
        switch (IR & 0x1F) {
        case 0: mImm(); break;
        case 4: mZp(); break;
        case 0xC: mAbs(); break;
        case 0x14: mZpX(); break;
        case 0x1C: mAbsX(); break;
        }
        Addr &= 0xFFFF;
        switch ((IR & 0xE0) >> 5) {
        case 0: if (TIGHTLY(!(IR & 4))) {            /* BRK */
                    push((PC + 2 - 1) >> 8); push((PC + 2 - 1) & 0xFF); push(ST | B); ST |= I;
                    PC = RD(0xFFFE) + (RD(0xFFFF) << 8) - 1; Cycles = 7;
                } else if (RARELY(IR == 0x1C)) Cycles -= SamePage;
                break;
        case 1: if (CALMLY(IR & 0xF)) {
                    if (MOSTLY(!(IR & 0x10))) { ST &= 0x3D; ST |= (RD(Addr) & 0xC0) | ((!(A & RD(Addr))) << 1); }  /* BIT */
                    else if (RARELY(IR == 0x3C)) Cycles -= SamePage;
                } else {                             /* JSR */
                    push((PC + 2 - 1) >> 8); push((PC + 2 - 1) & 0xFF);
                    PC = RD(Addr) + RD(Addr + 1) * 256 - 1; Cycles = 6;
                }
                break;
        case 2: if (MOSTLY(IR & 0xF)) {
                    if (MOSTLY(IR == 0x4C)) {        /* JMP (upstream's NMI workaround for code in the CIA registers) */
                        PC = (RARELY(cRSID_C64.RealSIDmode && cRSID_C64.NMI && (PrevPC == 0xDC02 || PrevPC == 0xDC04)))
                             ? (unsigned int)((0x800 + (Addr & 0xFF)) - 1) : (Addr - 1);
                        Cycles = 3; (void)RD(Addr + 1);  /* the high byte's read (acks a CIA IRQ in some tunes) */
                    } else if (RARELY(IR == 0x5C)) Cycles -= SamePage;
                } else {                             /* RTI */
                    ST = pop(); T = pop(); PC = (pop() << 8) + T - 1; Cycles = 6;
                    if (LIKELY(cRSID_C64.Returned && SP >= 0xFF)) { ++PC; ic = 0xFE; goto sw_cpu_done; }
                }
                break;
        case 3: if (CALMLY(IR & 0xF)) {
                    if (MOSTLY(IR == 0x6C)) {        /* JMP () with the page wrap */
                        PC = RD((Addr & 0xFF00) + ((Addr + 1) & 0xFF));
                        PC = (PC << 8) + RD(Addr) - 1; Cycles = 5;
                    } else if (RARELY(IR == 0x7C)) Cycles -= SamePage;
                } else {                             /* RTS */
                    if (RARELY(SP >= 0xFF)) { cRSID_C64.Returned = 1; ic = 0xFF; goto sw_cpu_done; }
                    T = pop(); PC = (pop() << 8) + T; Cycles = 6;
                }
                break;
        case 4: if (MOSTLY(IR & 4)) { WR2(Addr, Y); } break;  /* STY */
        case 5: Y = RD(Addr); setNZbyY(); Cycles -= SamePage; break;  /* LDY */
        case 6: if (MOSTLY(!(IR & 0x10))) { T = Y - RD(Addr); setNZCbySub(T); }  /* CPY */
                else if (RARELY(IR == 0xDC)) Cycles -= SamePage;
                break;
        case 7: if (MOSTLY(!(IR & 0x10))) { T = X - RD(Addr); setNZCbySub(T); }  /* CPX */
                else if (RARELY(IR == 0xFC)) Cycles -= SamePage;
                break;
        }
    }

    ++PC;
    ic = (unsigned char)Cycles;
sw_cpu_done:;
}
