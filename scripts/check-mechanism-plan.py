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
