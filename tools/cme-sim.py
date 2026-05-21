# cme_sim.py

import sys

class CMEException(Exception):
    pass

class BankRevokedException(CMEException):
    pass

class ContextBank:
    def __init__(self, bank_id, initial_group=0, max_depth=4):
        self.bank_id = bank_id
        self.group_stack = [initial_group]
        self.active = False    # True if bank is in use (simulated)
        self.max_depth = max_depth

    @property
    def current_group(self):
        return self.group_stack[-1]

    def push_group(self, group_id):
        if len(self.group_stack) >= self.max_depth:
            raise CMEException(f"Bank {self.bank_id}: group stack overflow!")
        self.group_stack.append(group_id)

    def pop_group(self):
        if len(self.group_stack) <= 1:
            raise CMEException(f"Bank {self.bank_id}: cannot pop root group!")
        return self.group_stack.pop()

    def __repr__(self):
        active = "*" if self.active else " "
        stack = "→".join(map(str, self.group_stack))
        return f"Bank{self.bank_id}{active}[{stack}]"

class Hart:
    def __init__(self, hart_id):
        self.hart_id = hart_id
        self.assigned_bank = None
        self.current_group = 0
        self.running_vm = None

    def assign_bank(self, bank: ContextBank):
        self.assigned_bank = bank
        bank.active = True

    def release_bank(self):
        if self.assigned_bank:
            self.assigned_bank.active = False
            self.assigned_bank = None

    def __repr__(self):
        bank = f"B{self.assigned_bank.bank_id}" if self.assigned_bank else "-"
        return f"Hart{self.hart_id}(bank={bank}, group={self.current_group}, vm={self.running_vm})"

class VM:
    def __init__(self, name, group_id, parent=None):
        self.name = name
        self.group_id = group_id
        self.parent = parent
        self.child_vms = []
        self.banks = []

    def add_bank(self, bank: ContextBank):
        self.banks.append(bank)

    def add_child_vm(self, vm):
        self.child_vms.append(vm)

    def __repr__(self):
        return f"VM({self.name}, group={self.group_id}, banks={[b.bank_id for b in self.banks]})"

class CMEController:
    def __init__(self, num_banks=8, num_harts=3):
        self.banks = [ContextBank(i) for i in range(num_banks)]
        self.harts = [Hart(i) for i in range(num_harts)]
        self.next_group_id = 1
        self.vms = []

    def create_vm(self, parent_vm=None, bank_ids=None):
        group_id = self.next_group_id
        self.next_group_id += 1
        vm = VM(name=f"VM{group_id}", group_id=group_id, parent=parent_vm)
        if parent_vm:
            parent_vm.add_child_vm(vm)
        self.vms.append(vm)
        for bid in bank_ids or []:
            bank = self.banks[bid]
            bank.push_group(group_id)
            vm.add_bank(bank)
        return vm

    def assign_bank_to_hart(self, hart_id, bank_id, vm):
        hart = self.harts[hart_id]
        bank = self.banks[bank_id]
        if bank.current_group != vm.group_id:
            raise CMEException(f"Cannot assign bank {bank_id} to VM{vm.group_id}: not owned by group")
        hart.assign_bank(bank)
        hart.current_group = vm.group_id
        hart.running_vm = vm.name
        print(f"[INFO] Hart{hart_id} assigned to Bank{bank_id} (Group {vm.group_id})")

    def revoke_group(self, group_id, reason="by parent"):
        print(f"\n[ADMIN] Revoking group {group_id} {reason}...")
        for bank in self.banks:
            if group_id in bank.group_stack:
                while bank.current_group != group_id and len(bank.group_stack) > 1:
                    bank.pop_group()
                if bank.current_group == group_id:
                    if bank.active:
                        print(f"[EXCPT] Bank {bank.bank_id} active in group {group_id}: triggering exception")
                        self.trigger_exception(bank, group_id)
                        # On real hardware, bank would be zeroed or migrated here
                    bank.pop_group()
                    print(f"[INFO] Bank {bank.bank_id} returned to group {bank.current_group}")

    def trigger_exception(self, bank, group_id):
        # Find which hart uses this bank
        for hart in self.harts:
            if hart.assigned_bank == bank and hart.current_group == group_id:
                print(f"[EXCPT] Hart{hart.hart_id}: BANK_REVOKED (Bank {bank.bank_id}, group {group_id})")
                # Simulate handler: clean up and release bank
                hart.release_bank()
                print(f"[CLEAN] Hart{hart.hart_id}: released Bank {bank.bank_id}")

    def print_state(self):
        print("\n==== CME SYSTEM STATE ====")
        print("Banks:")
        for bank in self.banks:
            print(f"  {bank}")
        print("Harts:")
        for hart in self.harts:
            print(f"  {hart}")
        print("VMs:")
        for vm in self.vms:
            print(f"  {vm}")
        print("=========================\n")

def scenario_demo():
    cme = CMEController(num_banks=8, num_harts=3)

    print("=== CME DEMO: Host (L0), VM1 (L1), VM2 (L2) ===")
    # L0 (host) delegates banks 0-3 to VM1
    vm1 = cme.create_vm(parent_vm=None, bank_ids=[0,1,2,3])
    # VM1 delegates banks 1-2 to VM2
    vm2 = cme.create_vm(parent_vm=vm1, bank_ids=[1,2])

    cme.print_state()

    # Assign Hart0 to Bank1 (used by VM2)
    cme.assign_bank_to_hart(0, 1, vm2)
    # Assign Hart1 to Bank3 (used by VM1)
    cme.assign_bank_to_hart(1, 3, vm1)

    cme.print_state()

    # L0 (admin) revokes group for VM2
    cme.revoke_group(vm2.group_id, reason="(simulate parent kill)")
    cme.print_state()

    # L0 (admin) revokes group for VM1
    cme.revoke_group(vm1.group_id, reason="(simulate host reclaim)")
    cme.print_state()

if __name__ == "__main__":
    scenario_demo()

