"""Real browser acceptance against generated offline documents and downloads."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[3]

class ViewerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = Path(os.environ['CHEMVIEWER_PORTABLE_BINARY']).resolve()
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close(); cls.playwright.stop()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.context = self.browser.new_context(accept_downloads=True, viewport={'width': 1200, 'height': 900})
        self.addCleanup(self.context.close)
        self.page = self.context.new_page()
        self.errors = []; self.network = []
        self.page.on('pageerror', lambda error: self.errors.append(str(error)))
        self.page.on('request', lambda request: self.network.append(request.url) if request.url.startswith(('http:', 'https:')) else None)

    def open(self, source):
        output = self.root/'viewer.html'
        subprocess.run([str(self.binary), str(source), '--output', str(output)], check=True, capture_output=True)
        self.page.goto(output.as_uri())
        self.page.wait_for_function("document.getElementById('title').textContent !== 'ChemViewer'")
        if self.page.locator('#frame option').count():
            self.page.wait_for_function('projected.length > 0')

    def assert_clean(self):
        self.assertEqual(self.errors, []); self.assertEqual(self.network, [])

    def test_render_rotate_fit_measure_resize_and_export(self):
        self.open(ROOT/'Tests/fixtures/water.xyz')
        canvas = self.page.locator('#viewport')
        self.assertGreater(self.page.evaluate("ctx.getImageData(0,0,canvas.width,canvas.height).data.filter((x,i)=>i%4===0&&x>80).length"), 50)
        before = canvas.screenshot()
        box = canvas.bounding_box(); x=box['x']+box['width']/2; y=box['y']+box['height']/2
        self.page.mouse.move(x,y); self.page.mouse.down(); self.page.mouse.move(x+90,y+30,steps=10); self.page.mouse.up()
        self.assertNotEqual(before, canvas.screenshot())
        self.page.locator('#fit').click()
        self.page.wait_for_function('yaw === 0 && pitch === 0')
        for index in [0,1]:
            point = self.page.evaluate(f'({{x:projected[{index}].x/(devicePixelRatio||1),y:projected[{index}].y/(devicePixelRatio||1)}})')
            self.page.mouse.click(box['x']+point['x'],box['y']+point['y'])
        self.assertIn('0.95720 Å', self.page.locator('#selection').inner_text())
        self.page.set_viewport_size({'width':800,'height':700})
        self.page.wait_for_function('canvas.width === Math.round(canvas.clientWidth*(devicePixelRatio||1))')
        with self.page.expect_download() as download: self.page.locator('#xyz').click()
        target=self.root/'water.xyz'; download.value.save_as(target)
        self.assertEqual(target.read_text().splitlines()[0], '3')
        self.assertIn('H 0.957', target.read_text())
        with self.page.expect_download() as download: self.page.locator('#png').click()
        target=self.root/'water.png'; download.value.save_as(target)
        self.assertEqual(target.read_bytes()[:8], b'\x89PNG\r\n\x1a\n')
        self.assert_clean()

    def test_trajectory_energy_playback_and_missing_data(self):
        self.open(ROOT/'Tests/fixtures/energy-path.xyz')
        self.assertGreater(self.page.locator('#frame option').count(),1)
        self.page.locator('#next').click(); self.assertEqual(self.page.locator('#frame').input_value(),'1')
        self.page.locator('#previous').click(); self.assertEqual(self.page.locator('#frame').input_value(),'0')
        self.page.locator('#play').click(); self.page.wait_for_function('frame > 0')
        self.page.locator('#play').click(); self.assertEqual(self.page.locator('#play').inner_text(),'Play trajectory')
        self.assertIn('Eh',self.page.locator('#status').inner_text())
        self.assert_clean()

    def test_imaginary_mode_animation_preserves_export_and_separate_properties(self):
        self.open(ROOT/'Tests/fixtures/integrated-building/synthetic-modes.out')
        self.assertIn('-250 (imaginary)', self.page.locator('#mode').inner_text())
        self.page.locator('#mode').select_option('2')
        self.assertIn('Animated display',self.page.locator('#status').inner_text())
        first=self.page.locator('#viewport').screenshot()
        self.page.wait_for_timeout(300)
        self.assertNotEqual(first,self.page.locator('#viewport').screenshot())
        self.assertIn('Raman activity: unavailable',self.page.locator('#properties').text_content())
        with self.page.expect_download() as download: self.page.locator('#xyz').click()
        target=self.root/'equilibrium.xyz'; download.value.save_as(target)
        self.assertIn('O 0 0 0',target.read_text())
        self.assert_clean()

    def test_source_is_text_and_empty_geometry_is_explicit(self):
        source=self.root/'inert.xyz'
        source.write_text('1\n</script><img src=x onerror="window.injected=true"> μ\nHe 0 0 0\n',encoding='utf-8')
        self.open(source)
        self.assertEqual(self.page.locator('#source img').count(),0)
        self.assertFalse(self.page.evaluate('Boolean(window.injected)'))
        self.assertIn('μ',self.page.locator('#source').text_content())
        self.assertIn('unavailable',self.page.locator('#status').inner_text())
        self.assert_clean()

    def test_source_only_input_does_not_invent_atoms_or_energy(self):
        source=self.root/'template.inp'
        source.write_text('! HF STO-3G\n%pal nprocs 2 end\n',encoding='utf-8')
        self.open(source)
        self.assertEqual(self.page.locator('#frame option').count(),0)
        self.assertTrue(self.page.locator('#xyz').is_disabled())
        self.assertTrue(self.page.locator('#png').is_disabled())
        self.assertIn('No Cartesian geometry',self.page.locator('#status').inner_text())
        self.assertIn('nprocs 2',self.page.locator('#source').text_content())
        self.assert_clean()

if __name__ == '__main__': unittest.main(verbosity=2)
