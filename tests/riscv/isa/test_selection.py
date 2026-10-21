#!/usr/bin/env python3

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path.cwd()


class IsaSelectionTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue((ROOT / 'config.mk').is_file(), 'Run from a configured build root')
        self.directory = tempfile.TemporaryDirectory(dir=ROOT / 'tests/riscv/isa')
        self.addCleanup(self.directory.cleanup)
        self.fixture = Path(self.directory.name)
        self.images = self.fixture / 'images'
        self.images.mkdir()
        self.engine = self.fixture / 'rtlsim'
        self.engine.mkdir()
        # GNU make propagates --eval to recursive model builds.
        (self.engine / 'Makefile').write_text('.DEFAULT_GOAL := all\nall:\n\t@:\n')
        executable = self.engine / 'rtlsim'
        executable.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$ISA_SELECTION_LOG"\n'
                              'exit "${ISA_SELECTION_STATUS:-0}"\n')
        executable.chmod(0o755)
        self.log = self.fixture / 'calls'

    def run_make(self, target, configs='', engine='verilator', status=0, extra=()):
        return subprocess.run(
            ['make', '-s', '-C', str(ROOT / 'tests/riscv/isa'),
             '-o', str(ROOT / 'tests/riscv/upstream/.installed'),
             f'CONFIGS={configs}', f'SIMULATOR={engine}',
             f'SIM_DIR={self.fixture}', f'ISA_DIR={self.images}',
             '--eval=print-selection:;@echo "$(P_32A)|$(P_32C)"', target, *extra],
            env=dict(os.environ, ISA_SELECTION_LOG=str(self.log),
                     ISA_SELECTION_STATUS=str(status)), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def test_extension_selection(self):
        for configs, expected in [('', '|'),
                                  ('-DVX_CFG_EXT_A_ENABLE', 'rv32ua-p|'),
                                  ('-DVX_CFG_EXT_C_ENABLE', '|rv32uc-p')]:
            with self.subTest(configs=configs):
                result = self.run_make('print-selection', configs)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(result.stdout.strip(), expected)

    def test_disabled_extensions_fail_before_engine_use(self):
        for engine in ('verilator', 'vcs'):
            for extension in ('a', 'c'):
                with self.subTest(engine=engine, extension=extension):
                    result = self.run_make(f'run-rtlsim-32{extension}', engine=engine)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn('requires an enabled ISA extension', result.stdout)
                    self.assertFalse(self.log.exists())

    def test_invalid_configuration_fails(self):
        result = self.run_make('print-selection', '-DVX_CFG_NUM_THREADS=invalid')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('could not resolve ISA configuration', result.stdout)
        self.assertFalse(self.log.exists())

    def test_missing_binaries_fail(self):
        (self.images / 'rv32uc-p-fixture.dump').touch()
        for engine in ('verilator', 'vcs'):
            with self.subTest(engine=engine):
                result = self.run_make('run-rtlsim-32c', '-DVX_CFG_EXT_C_ENABLE', engine)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn('no ISA binaries for rv32uc-p', result.stdout)
                self.assertFalse(self.log.exists())

    def test_selected_binary_status_is_preserved(self):
        image = self.images / 'rv32uc-p-fixture'
        image.touch()
        for engine in ('verilator', 'vcs'):
            for status in (0, 37):
                with self.subTest(engine=engine, status=status):
                    self.log.unlink(missing_ok=True)
                    result = self.run_make('run-rtlsim-32c', '-DVX_CFG_EXT_C_ENABLE',
                                           engine, status)
                    self.assertEqual(result.returncode == 0, status == 0, result.stdout)
                    self.assertEqual(self.log.read_text().splitlines(), [str(image)])

    def test_existing_exclusions_are_preserved(self):
        for name in ('rv32ui-p-add', 'rv32ui-p-fence_i', 'rv32ui-p-ma_data'):
            (self.images / name).touch()
        for engine in ('verilator', 'vcs'):
            with self.subTest(engine=engine):
                self.log.unlink(missing_ok=True)
                result = self.run_make('run-rtlsim-32i', engine=engine)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.log.read_text().splitlines(),
                                 [str(self.images / 'rv32ui-p-add')])

    def test_parallel_goals_do_not_overlap_engine_builds(self):
        guard = self.fixture / 'building'
        (self.engine / 'Makefile').write_text(
            f'.DEFAULT_GOAL := all\nall:\n\t@mkdir "{guard}"\n'
            f'\t@sleep 0.1\n\t@rmdir "{guard}"\n')
        for name in ('rv32ui-p-add', 'rv32um-p-mul'):
            (self.images / name).touch()
        for engine in ('verilator', 'vcs'):
            with self.subTest(engine=engine):
                self.log.unlink(missing_ok=True)
                result = self.run_make('run-rtlsim-32i', engine=engine,
                                       extra=('-j2', 'run-rtlsim-32im'))
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(len(self.log.read_text().splitlines()), 3)


if __name__ == '__main__':
    unittest.main()
