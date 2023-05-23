#ifndef DPCRUN_H
#define DPCRUN_H

#include <iostream>
#include <iomanip>

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <cstring>

#include <fstream>

#include <vector>
#include <getopt.h>

template <typename counterType> class Counter
{
public: 
	Counter(counterType bottom, counterType top = 0, counterType value = 0) : m_bottom(bottom), m_top(top), m_value(value)
    {
    }

	virtual Counter& operator ++ ()
    {
        m_value++;
        if ((m_top) && ((m_value >= m_top) || (m_value < m_bottom)))
        {
            m_value = m_bottom;
        }
        return *this;
    }

	virtual Counter& operator -- ()
    {
        m_value--;
		if ((m_top) && ((m_value >= m_top) || (m_value < m_bottom)))
        {
            m_value = m_top;
        }
        return *this;
    }

	virtual Counter operator++ (int)
    {
       Counter temp(m_bottom, m_top, m_value);
       return ++temp;
    }

	virtual Counter operator-- (int)
    {
       Counter temp(m_bottom, m_top, m_value);
       return --temp;
    }

	virtual counterType pos()
    {
        return m_value;
    }

	virtual counterType size()
	{
		return m_top - m_bottom;
	}

	virtual void pos(counterType val)
    {
        if ((val >= m_bottom) && (val < m_top))
        {
            m_value = val;
        }
    }

	virtual void reset()
    {
        m_value = m_bottom;
    }

private:
	counterType m_bottom;
	counterType m_top;
	counterType m_value;
};

template <typename MemType, typename countType> class Memory : public Counter<countType>
{
public:
	Memory(countType bottom, countType top, MemType* data = NULL) : 
			Counter<countType>(bottom, top), m_memoryInited(false)
	{
		m_memory = static_cast<MemType*>(calloc(sizeof(MemType)*(top - bottom), 1));
		if (data)
		{
			memcpy(m_memory, data, top - bottom);
		}
	}
	virtual bool Ready(){
		return m_memoryInited;
	}
	virtual MemType& operator * ()
	{
		m_memoryInited = true;
		return m_memory[this->pos()];
	}

private:
	MemType * m_memory;
	bool m_memoryInited;
};

class CppMachine{
public:
	size_t IRET;
	size_t CLK_UNHALTED;
	Memory <char, size_t>& codeRAM;
	Memory <char, size_t>& dataRAM;
	Counter <size_t>& loopCounter;

	CppMachine(Memory <char, size_t>& codeRam,
				Memory <char, size_t>& dataRam,
				Counter <size_t>& loopCnt) : 
				codeRAM(codeRam), dataRAM(dataRam), loopCounter(loopCnt),
				IRET(0), CLK_UNHALTED(0)
	{
	}
};

int LoopLookup(CppMachine& machine, bool reverse);
int stepCpp(CppMachine& machine);
int ExecCode(char* code, size_t size, int stepMode);
std::ifstream::pos_type filesize(const char* filename);

#endif
