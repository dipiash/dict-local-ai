import json
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPORT = Path(__file__).resolve().parents[1] / "evaluation" / 'report-diarization.py'
spec = importlib.util.spec_from_file_location('report', REPORT)
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


class ReportTests(unittest.TestCase):
    def test_matches_complete_absolute_windows_and_excludes_padded_high_probability(self):
        def window(stage, offset, peak, complete):
            return {'start': 750, 'end': 770, 'stage': stage, 'metrics': {
                'chunkOffsetSeconds': offset, 'speechProbabilityMean': peak / 2,
                'speechProbabilityMax': peak, 'windowComplete': complete}}
        observations = [
            window('segmentation_window', 750, 0.1, 1),
            window('segmentation_window', 766, 0.067, 1),
            window('replay_20s_segmentation_window', 0, 0.1, 1),
            window('replay_20s_segmentation_window', 16, 0.998, 0),
            {'start': 750, 'end': 770, 'stage': 'replay_20s_summary',
             'metrics': {'replayWindowStart': 750}},
        ]
        matched = report.matched_window_summaries(observations)[0]
        self.assertEqual(matched['commonCompleteWindows'], 1)
        self.assertEqual(matched['maxPeakSummaryDifference'], 0)
        for item in observations:
            item['metrics'].pop('windowComplete', None)
        matched = report.matched_window_summaries(observations)[0]
        self.assertEqual(matched['commonCompleteWindows'], 0)
        self.assertIsNone(matched['maxPeakSummaryDifference'])

    def test_current_pipeline_reports_are_readable_without_transcript_text(self):
        for with_observations in (False, True):
            with self.subTest(with_observations=with_observations), tempfile.TemporaryDirectory() as directory:
                audit = {
                    'schemaVersion': 3, 'source': 'test', 'method': 'nemotron3-fast128',
                    'duration': 800, 'words': [{'start': 751, 'end': 752, 'reason': 'no_turn',
                                              'text': 'PRIVATE RECOGNIZED WORD'}],
                }
                if with_observations:
                    audit['pipelineObservations'] = [{
                        'start': 750, 'end': 770, 'stage': 'segmentation',
                        'metrics': {'frameObservations': 100}, 'note': 'test probe',
                    }]
                    if with_observations:
                        audit['pipelineObservations'].append({
                            'start': 751, 'end': 752, 'stage': 'embedding_window',
                            'metrics': {'reasonCode': 5}, 'note': 'matrix_mismatch',
                        })
                path = Path(directory) / 'audit.json'
                path.write_text(json.dumps(audit))
                result = subprocess.run([sys.executable, str(REPORT), str(path)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('unknown: 1', result.stdout)
                self.assertNotIn('PRIVATE RECOGNIZED WORD', result.stdout)
                if with_observations:
                    self.assertIn('segmentation | frameObservations=100', result.stdout)
