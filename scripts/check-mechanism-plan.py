#!/usr/bin/env python3
"""Check the synthetic mechanism exported by the native acceptance harness."""
from collections import Counter
from math import dist, isclose
from pathlib import Path
import sys

from ase.io import read
from chemrefine import mechanism, mechanism_batch
from chemrefine.config import load_config


def check(config_path: Path) -> None:
    config = load_config(config_path)
    stages = config.mechanism.stages
    assert [stage.name for stage in stages] == ["stage_1", "stage_2"]
    assert stages[0].reactant.initial_core.anchor == 2
    assert [stage.product.core.anchor for stage in stages] == [2, 2]
    assert stages[1].reactant.sources[0].select == "metal_complex"
    assert all(stage.charge == 0 and stage.multiplicity == 1 for stage in stages)
    reaction = stages[0]
    assert config.mechanism.seed == 73 and config.mechanism.conformers == 5
    assert reaction.ts_guesser.timeout_seconds == 321
    branches = (reaction.reactant.steps, reaction.product.steps, reaction.ts_guesser.scoring_steps, reaction.ts_steps)
    assert all([step.step for step in branch] == [1, 2] for branch in branches)
    assert len({step.template for branch in branches for step in branch}) == 8
    assert not stages[1].reactant.steps and not stages[1].product.steps
    first = reaction.reactant.steps[0]
    assert first.operation == "sp" and (config.template_dir / first.template).read_text() == "! HF def2-SVP\n"
    single_point = reaction.reactant.steps[1]
    assert single_point.engine == "pyscf" and single_point.operation == "sp"
    assert single_point.options == {"method": "hf", "basis": "sto-3g"}
    frequency = reaction.product.steps[1]
    assert frequency.operation == "freq"
    assert (config.template_dir / frequency.template).read_text() == "! PBE def2-SVP Freq\n"
    assert all(step.operation == "sp" for step in reaction.ts_guesser.scoring_steps)
    assert reaction.ts_steps[1].operation == "sp"
    variants = mechanism_batch.expand(config)
    assert len(variants) == len({variant.config.output_dir for variant in variants}) == 4
    combinations = set()
    for variant in variants:
        catalyst, substrate = [read(path) for path in variant.sources]
        halide = catalyst.get_chemical_symbols()[1]
        assert halide in {"Cl", "Br"}
        assert isclose(dist(*catalyst.positions), {"Cl": 2.1, "Br": 2.3}[halide], abs_tol=1e-7)
        shift = float(substrate.positions[1, 0])
        assert shift in {0.28, 0.30}
        combinations.add((halide, shift))
        assert variant.config.max_cores == 2 and variant.config.max_gpus == 0

        separation, rebinding = mechanism.plan(variant.config)
        expected_atoms = Counter({"Cu": 1, halide: 1, "N": 1, "H": 3})
        for plan, distance in ((separation, 4.2), (rebinding, 2.05)):
            for graph in (plan.reactant, plan.product):
                assert Counter(atom.GetSymbol() for atom in graph.GetAtoms()) == expected_atoms
            assert isclose(dist(*plan.mapping["core_coordinates"]), distance, abs_tol=1e-6)
            assert plan.mapping["bond_edits"] == 1
        assembly = separation.mapping["initial_core"]
        assert assembly["coordination_edits"] == 1
        assert isclose(dist(*assembly["core_coordinates"]), 2.1, abs_tol=1e-6)
        assert mechanism.maps(separation.product) == [1, 2, 3, 4, 5, 6]
        assert mechanism.maps(rebinding.reactant) == [1, 2, 7, 8, 9, 10]
        assert rebinding.mapping["sources"][0]["atom_maps"] == [1, 2]
        assert rebinding.mapping["sources"][1]["atom_maps"] == [7, 8, 9, 10]
    assert combinations == {("Cl", 0.28), ("Cl", 0.30), ("Br", 0.28), ("Br", 0.30)}
    print("MECHANISM_PLAN_PASS: four isolated combinations and eight stages, source and core distances, one bond edit per stage, conserved atom inventory and fresh reagent identities.")


if __name__ == "__main__":
    check(Path(sys.argv[1]))
