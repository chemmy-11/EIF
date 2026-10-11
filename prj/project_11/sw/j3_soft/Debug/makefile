################################################################################
# Automatically-generated file. Do not edit!
################################################################################

-include ../makefile.init

RM := rm -rf

# All of the sources participating in the build are defined here
-include sources.mk
-include src/subdir.mk
-include subdir.mk
-include objects.mk

ifneq ($(MAKECMDGOALS),clean)
ifneq ($(strip $(S_UPPER_DEPS)),)
-include $(S_UPPER_DEPS)
endif
ifneq ($(strip $(C_DEPS)),)
-include $(C_DEPS)
endif
endif

-include ../makefile.defs

# Add inputs and outputs from these tool invocations to the build variables 
ELFSIZE += \
j3_soft.elf.size \


# All Target
all: j3_soft.elf secondary-outputs

# Tool invocations
j3_soft.elf: $(OBJS) ../src/lscript.ld $(USER_OBJS)
	@echo 'Building target: $@'
	@echo 'Invoking: MicroBlaze gcc linker'
	mb-gcc -Wl,-T -Wl,../src/lscript.ld -LD:/FPGA/prj/project_11/sw/mbplat/export/mbplat/sw/mbplat/standalone_domain/bsplib/lib -mlittle-endian -mcpu=v11.0 -mxl-soft-mul -Wl,--no-relax -Wl,--gc-sections -o "j3_soft.elf" $(OBJS) $(USER_OBJS) $(LIBS)
	@echo 'Finished building target: $@'
	@echo ' '

j3_soft.elf.size: j3_soft.elf
	@echo 'Invoking: MicroBlaze Print Size'
	mb-size j3_soft.elf  |tee "j3_soft.elf.size"
	@echo 'Finished building: $@'
	@echo ' '

# Other Targets
clean:
	-$(RM) $(EXECUTABLES)$(OBJS)$(S_UPPER_DEPS)$(C_DEPS)$(ELFSIZE) j3_soft.elf
	-@echo ' '

secondary-outputs: $(ELFSIZE)

.PHONY: all clean dependents

-include ../makefile.targets
