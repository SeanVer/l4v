(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

chapter "Machine Operations"

theory MachineOps
imports
  "../../../lib/$L4V_ARCH/WordSetup"
  "../../../lib/Monad_WP/NonDetMonad"
  "../MachineMonad"
begin

section "Wrapping and Lifting Machine Operations"

text {*
  Most of the machine operations below work on the underspecified 
  part of the machine state @{typ machine_state_rest} and cannot fail. 
  We could express the latter by type (leaving out the failure flag),
  but if we later wanted to implement them,
  we'd have to set up a new hoare-logic
  framework for that type. So instead, we provide a wrapper for these
  operations that explicitly ignores the fail flag and sets it to
  False. Similarly, these operations never return an empty set of
  follow-on states, which would require the operation to fail.
  So we explicitly make this (non-existing) case a null operation.

  All this is done only to avoid a large number of axioms (2 for each operation).
*}

context Arch begin global_naming X64

section "The Operations"

consts'
  memory_regions :: "(paddr \<times> paddr) list" (* avail_p_regs *)
  device_regions :: "(paddr \<times> paddr) list" (* dev_p_regs *)

definition
  getMemoryRegions :: "(paddr * paddr) list machine_monad"
  where "getMemoryRegions \<equiv> return memory_regions"

consts'
  getDeviceRegions_impl :: "unit machine_rest_monad"
  getDeviceRegions_val :: "machine_state \<Rightarrow> (paddr * paddr) list"

definition
  getDeviceRegions :: "(paddr * paddr) list machine_monad"
where
  "getDeviceRegions \<equiv> return device_regions"

consts'
  getKernelDevices_impl :: "unit machine_rest_monad"
  getKernelDevices_val :: "machine_state \<Rightarrow> (paddr * machine_word) list"

definition
  getKernelDevices :: "(paddr * machine_word) list machine_monad"
where
  "getKernelDevices \<equiv> do
    machine_op_lift getKernelDevices_impl;
    gets getKernelDevices_val
  od"


definition
  loadWord :: "machine_word \<Rightarrow> machine_word machine_monad"
  where "loadWord p \<equiv> do m \<leftarrow> gets underlying_memory;
                         assert (p && mask 3 = 0);
                         return (word_rcat (map (\<lambda>i. m (p + (of_int i))) [0 .. 7]))
                      od"

definition
  storeWord :: "machine_word \<Rightarrow> machine_word \<Rightarrow> unit machine_monad"
  where "storeWord p w \<equiv> do 
                            assert (p && mask 3 = 0);
                            modify (underlying_memory_update (
                                      fold (\<lambda>i m. m((p + (of_int i)) := word_rsplit w ! (nat i))) [0 .. 7]))
                         od"

lemma upto0_7_def:
  "[0..7] = [0,1,2,3,4,5,6,7]" by eval

lemma loadWord_storeWord_is_return:
  "p && mask 3 = 0 \<Longrightarrow> (do w \<leftarrow> loadWord p; storeWord p w od) = return ()"
  apply (rule ext)
  by (simp add: loadWord_def storeWord_def bind_def assert_def return_def 
    modify_def gets_def get_def eval_nat_numeral put_def upto0_7_def
    word_rsplit_rcat_size word_size)


text {* This instruction is required in the simulator, only. *}
definition
  storeWordVM :: "machine_word \<Rightarrow> machine_word \<Rightarrow> unit machine_monad"
  where "storeWordVM w p \<equiv> return ()"

consts'
  configureTimer_impl :: "unit machine_rest_monad"
  configureTimer_val :: "machine_state \<Rightarrow> irq"

definition
  configureTimer :: "irq machine_monad"
where
  "configureTimer \<equiv> do 
    machine_op_lift configureTimer_impl;
    gets configureTimer_val
  od"

consts' (* XXX: replaces configureTimer in new boot code
          TODO: remove configureTimer when haskell updated *)
  initTimer_impl :: "unit machine_rest_monad"
definition
  initTimer :: "unit machine_monad"
where "initTimer \<equiv> machine_op_lift initTimer_impl"

consts'
  resetTimer_impl :: "unit machine_rest_monad"

definition
  resetTimer :: "unit machine_monad"
where "resetTimer \<equiv> machine_op_lift resetTimer_impl"

consts'
  invalidateTLB_impl :: "unit machine_rest_monad"
definition
  invalidateTLB :: "unit machine_monad"
where "invalidateTLB \<equiv> machine_op_lift invalidateTLB_impl"

lemmas cache_machine_op_defs = invalidateTLB_def

definition
  debugPrint :: "unit list \<Rightarrow> unit machine_monad"
where
  debugPrint_def[simp]:
 "debugPrint \<equiv> \<lambda>message. return ()"


-- "Interrupt controller operations"

text {* 
  @{term getActiveIRQ} is now derministic.
  It 'updates' the irq state to the reflect the passage of
  time since last the irq was gotten, then it gets the active 
  IRQ (if there is one).
*}
definition
  getActiveIRQ :: "(irq option) machine_monad"
where
  "getActiveIRQ \<equiv> do
    is_masked \<leftarrow> gets $ irq_masks;
    modify (\<lambda>s. s \<lparr> irq_state := irq_state s + 1 \<rparr>);
    active_irq \<leftarrow> gets $ irq_oracle \<circ> irq_state;
    if is_masked active_irq \<or> active_irq = 0xFF
    then return None
    else return ((Some active_irq) :: irq option)
  od"

definition
  maskInterrupt :: "bool \<Rightarrow> irq \<Rightarrow> unit machine_monad"
where
  "maskInterrupt m irq \<equiv> 
  modify (\<lambda>s. s \<lparr> irq_masks := (irq_masks s) (irq := m) \<rparr>)"

text {* Does nothing on imx31 *}
definition
  ackInterrupt :: "irq \<Rightarrow> unit machine_monad"
where
  "ackInterrupt \<equiv> \<lambda>irq. return ()"

text {* Does nothing on imx31 *}
definition
  setInterruptMode :: "irq \<Rightarrow> bool \<Rightarrow> bool \<Rightarrow> unit machine_monad"
where
  "setInterruptMode \<equiv> \<lambda>irq levelTrigger polarityLow. return ()"

section "Memory Clearance"

text {* Clear memory contents to recycle it as user memory *}
definition
  clearMemory :: "machine_word \<Rightarrow> nat \<Rightarrow> unit machine_monad"
  where
 "clearMemory ptr bytelength \<equiv> mapM_x (\<lambda>p. storeWord p 0) [ptr, ptr + word_size .e. ptr + (of_nat bytelength) - 1]"
                                                                          
definition
  clearMemoryVM :: "machine_word \<Rightarrow> nat \<Rightarrow> unit machine_monad"
  where
  "clearMemoryVM ptr bits \<equiv> return ()"

text {*
  Initialize memory to be used as user memory.
  Note that zeroing out the memory is redundant in the specifications.
  In any case, we cannot abstract from the call to cleanCacheRange,
  which appears in the implementation.
*}
abbreviation (input) "initMemory == clearMemory"

text {*
  Free memory that had been initialized as user memory.
  While freeing memory is a no-op in the implementation,
  we zero out the underlying memory in the specifications to avoid garbage.
  If we know that there is no garbage,
  we can compute from the implementation state
  what the exact memory content in the specifications is.
*}
definition
  freeMemory :: "machine_word \<Rightarrow> nat \<Rightarrow> unit machine_monad"
  where
 "freeMemory ptr bits \<equiv>
  mapM_x (\<lambda>p. storeWord p 0) [ptr, ptr + word_size  .e.  ptr + 2 ^ bits - 1]"


section "User Monad"

type_synonym user_context = "register \<Rightarrow> machine_word"

type_synonym 'a user_monad = "(user_context, 'a) nondet_monad"

definition
  getRegister :: "register \<Rightarrow> machine_word user_monad" 
where
  "getRegister r \<equiv> gets (\<lambda>uc. uc r)"

definition
  setRegister :: "register \<Rightarrow> machine_word \<Rightarrow> unit user_monad" 
where
  "setRegister r v \<equiv> modify (\<lambda>uc. uc (r := v))"

definition
  "getRestartPC \<equiv> getRegister FaultInstruction" 

definition
  "setNextPC \<equiv> setRegister NextIP"
 
consts'
  initL2Cache_impl :: "unit machine_rest_monad"
definition
  initL2Cache :: "unit machine_monad"
where "initL2Cache \<equiv> machine_op_lift initL2Cache_impl"
 
definition getCurrentCR3 :: "Platform.X64.cr3 machine_monad"
  where
  "getCurrentCR3 \<equiv> undefined"
  
definition setCurrentCR3 :: "Platform.X64.cr3 \<Rightarrow> unit machine_monad"
  where
  "setCurrentCR3 \<equiv> undefined"
  
definition
mfence :: "unit machine_monad"
where
"mfence \<equiv> undefined"

consts'
  invalidateTLBEntry_impl :: "word64 \<Rightarrow> unit machine_rest_monad"

definition
invalidateTLBEntry :: "word64 \<Rightarrow> unit machine_monad"
where
"invalidateTLBEntry vptr \<equiv> machine_op_lift (invalidateTLBEntry_impl vptr)"

consts'
  invalidatePageStructureCache_impl :: "unit machine_rest_monad"
  
definition
  invalidatePageStructureCache :: "unit machine_monad" where
  "invalidatePageStructureCache \<equiv> machine_op_lift invalidatePageStructureCache_impl"
  
consts'
  resetCR3_impl :: "unit machine_rest_monad"
  
definition
  resetCR3 :: "unit machine_monad" where
  "resetCR3 \<equiv> machine_op_lift resetCR3_impl "

definition
firstValidIODomain :: "word16"
where
"firstValidIODomain \<equiv> undefined"

definition
numIODomainIDBits :: "nat"
where
"numIODomainIDBits \<equiv> undefined"

definition
hwASIDInvalidate :: "word64 \<Rightarrow> unit machine_monad"
where
"hwASIDInvalidate asid \<equiv> undefined"

definition
getFaultAddress :: "word64 machine_monad"
where
"getFaultAddress \<equiv> undefined"

definition
irqIntOffset :: "machine_word"
where
"irqIntOffset \<equiv> undefined"

definition
maxPCIBus :: "machine_word"
where
"maxPCIBus \<equiv> undefined"

definition
maxPCIDev :: "machine_word"
where
"maxPCIDev \<equiv> undefined"

definition
maxPCIFunc :: "machine_word"
where
"maxPCIFunc \<equiv> undefined"

definition
numIOAPICs :: "machine_word"
where
"numIOAPICs \<equiv> error []"

definition
ioapicIRQLines :: "machine_word"
where
"ioapicIRQLines \<equiv> undefined"

definition
ioapicMapPinToVector :: "machine_word \<Rightarrow> machine_word \<Rightarrow> machine_word \<Rightarrow> machine_word \<Rightarrow> machine_word \<Rightarrow> unit machine_monad"
where
"ioapicMapPinToVector ioapic pin level polarity vector \<equiv> undefined"

definition
"irqStateIRQIOAPICNew \<equiv> error []"

definition
"irqStateIRQMSINew \<equiv> error []"

datatype x64irqstate =
    X64IRQState

definition
updateIRQState :: "irq \<Rightarrow> x64irqstate \<Rightarrow> unit machine_monad"
where
"updateIRQState arg1 arg2 \<equiv> error []"

(*FIXME: How to deal with this directly? *)
definition
IRQ :: "word8 \<Rightarrow> irq"
where
"IRQ \<equiv> id"

(* FIXME x64: More underspecified operations *)

definition
in8 :: "word16 \<Rightarrow> machine_word machine_monad"
where
"in8 \<equiv> error []"

definition
in16 :: "word16 \<Rightarrow> machine_word machine_monad"
where
"in16 \<equiv> error []"

definition
in32 :: "word16 \<Rightarrow> machine_word machine_monad"
where
"in32 \<equiv> error []"

definition
out8 :: "word16 \<Rightarrow> word8 \<Rightarrow> unit machine_monad"
where
"out8 \<equiv> error []"

definition
out16 :: "word16 \<Rightarrow> word16 \<Rightarrow> unit machine_monad"
where
"out16 \<equiv> error []"

definition
out32 :: "word16 \<Rightarrow> word32 \<Rightarrow> unit machine_monad"
where
"out32 \<equiv> error []"

end


translations
  (type) "'a X64.user_monad" <= (type) "(X64.register \<Rightarrow> X64.machine_word, 'a) nondet_monad"


end
