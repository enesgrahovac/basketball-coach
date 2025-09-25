"""
Model evaluation utilities for basketball shot analysis.
Handles model inference, performance measurement, and result comparison.
"""

import time
import json
import os
from typing import Dict, List, Optional, Tuple, Any
from pathlib import Path
import pandas as pd
from google import genai
from google.genai import types
from tqdm import tqdm


class ModelEvaluator:
    """Evaluates different models and prompts on basketball shot analysis."""
    
    def __init__(self, gemini_api_key: str, output_dir: str = "data/model_outputs"):
        """Initialize evaluator with API credentials."""
        self.gemini_client = genai.Client(api_key=gemini_api_key)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Pricing information (approximate, update as needed)
        self.model_pricing = {
            "models/gemini-2.5-flash": {"input": 0.075, "output": 0.30},  # per 1M tokens
            "models/gemini-2.5-flash-lite": {"input": 0.075, "output": 0.30},
            "models/gemini-2.5-pro": {"input": 3.50, "output": 10.50},
        }
    
    def evaluate_model(
        self, 
        model_name: str, 
        prompt: str, 
        ground_truth_data: List[Dict],
        fps: int = 24,
        media_resolution: str = "MEDIUM",
        max_samples: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        Evaluate a specific model configuration on the dataset.
        
        Args:
            model_name: Gemini model name (e.g., "models/gemini-2.5-flash")
            prompt: The prompt to use for analysis
            ground_truth_data: List of ground truth entries
            fps: Frames per second for video processing
            media_resolution: Video resolution (LOW, MEDIUM, HIGH)
            max_samples: Maximum number of samples to evaluate (for testing)
        
        Returns:
            Dictionary with evaluation results and metrics
        """
        print(f"Evaluating {model_name} on {len(ground_truth_data)} samples...")
        
        if max_samples:
            ground_truth_data = ground_truth_data[:max_samples]
            print(f"Limited to {max_samples} samples for testing")
        
        results = []
        total_cost = 0.0
        
        for entry in tqdm(ground_truth_data, desc=f"Running {model_name}"):
            clip_id = entry['clip_id']
            video_path = Path(entry['video_path'])
            
            if not video_path.exists():
                print(f"Warning: Video not found for {clip_id}, skipping")
                continue
            
            try:
                # Run inference
                start_time = time.time()
                prediction, cost = self._run_inference(
                    model_name, prompt, video_path, fps, media_resolution
                )
                inference_time = time.time() - start_time
                
                # Store result
                result = {
                    'clip_id': clip_id,
                    'ground_truth': entry['ground_truth'],
                    'prediction': prediction,
                    'inference_time_s': inference_time,
                    'cost_usd': cost,
                    'model_name': model_name,
                    'fps': fps,
                    'media_resolution': media_resolution
                }
                results.append(result)
                total_cost += cost
                
            except Exception as e:
                print(f"Error processing {clip_id}: {e}")
                continue
        
        # Calculate metrics
        metrics = self._calculate_metrics(results)
        
        # Save results
        self._save_results(model_name, results, metrics, prompt, fps, media_resolution)
        
        return {
            'model_name': model_name,
            'total_samples': len(results),
            'total_cost_usd': total_cost,
            'average_inference_time_s': sum(r['inference_time_s'] for r in results) / len(results),
            'metrics': metrics,
            'results': results
        }
    
    def _run_inference(
        self, 
        model_name: str, 
        prompt: str, 
        video_path: Path, 
        fps: int, 
        media_resolution: str
    ) -> Tuple[Dict, float]:
        """Run inference on a single video and return prediction + cost estimate."""
        
        # Read video file
        with open(video_path, 'rb') as f:
            video_bytes = f.read()
        
        # Map resolution string to enum
        resolution_map = {
            "LOW": types.MediaResolution.MEDIA_RESOLUTION_LOW,
            "MEDIUM": types.MediaResolution.MEDIA_RESOLUTION_MEDIUM,
            "HIGH": types.MediaResolution.MEDIA_RESOLUTION_HIGH
        }
        
        # Generate content
        response = self.gemini_client.models.generate_content(
            model=model_name,
            contents=types.Content(
                parts=[
                    types.Part(
                        inline_data=types.Blob(data=video_bytes, mime_type="video/mp4"),
                        video_metadata=types.VideoMetadata(fps=fps)
                    ),
                    types.Part(text=prompt)
                ]
            ),
            config=types.GenerateContentConfig(
                media_resolution=resolution_map.get(media_resolution, types.MediaResolution.MEDIA_RESOLUTION_MEDIUM)
            )
        )
        
        # Extract prediction
        raw_text = response.candidates[0].content.parts[0].text if response.candidates else ""
        prediction = self._parse_model_output(raw_text)
        
        # Estimate cost (rough approximation)
        cost = self._estimate_cost(model_name, len(video_bytes), len(raw_text))
        
        return prediction, cost
    
    def _parse_model_output(self, raw_text: str) -> Dict:
        """Parse model output JSON, handling various formats."""
        try:
            # Clean up markdown formatting
            text = raw_text.strip()
            if text.startswith("```"):
                lines = text.split("\n")
                text = "\n".join(lines[1:-1]) if len(lines) > 2 else text
                if text.startswith("json"):
                    text = text[4:].strip()
            
            # Try to parse as JSON
            return json.loads(text)
            
        except json.JSONDecodeError:
            # Try to find JSON object in text
            start_idx = raw_text.find("{")
            end_idx = raw_text.rfind("}") + 1
            
            if start_idx >= 0 and end_idx > start_idx:
                try:
                    return json.loads(raw_text[start_idx:end_idx])
                except json.JSONDecodeError:
                    pass
            
            # Return error result
            return {
                "make_miss": None,
                "range": None,
                "confidence": 0.0,
                "tips": [],
                "error": "Failed to parse JSON",
                "raw_output": raw_text
            }
    
    def _estimate_cost(self, model_name: str, video_size_bytes: int, output_length: int) -> float:
        """Rough cost estimation based on model pricing."""
        if model_name not in self.model_pricing:
            return 0.0
        
        pricing = self.model_pricing[model_name]
        
        # Very rough approximation - video processing cost is hard to estimate
        # This is a placeholder that should be refined with actual usage data
        estimated_input_tokens = max(1000, video_size_bytes // 1000)  # Rough heuristic
        estimated_output_tokens = max(100, output_length // 4)  # ~4 chars per token
        
        input_cost = (estimated_input_tokens / 1_000_000) * pricing["input"]
        output_cost = (estimated_output_tokens / 1_000_000) * pricing["output"]
        
        return input_cost + output_cost
    
    def _calculate_metrics(self, results: List[Dict]) -> Dict[str, Any]:
        """Calculate evaluation metrics from results."""
        if not results:
            return {}
        
        # Prepare data for analysis
        shot_type_correct = 0
        result_correct = 0
        both_correct = 0
        valid_predictions = 0
        
        shot_type_confusion = {}
        result_confusion = {}
        confidence_scores = []
        
        for result in results:
            gt = result['ground_truth']
            pred = result['prediction']
            
            # Skip if prediction failed
            if pred.get('error'):
                continue
            
            valid_predictions += 1
            
            # Shot type accuracy
            gt_shot_type = gt['shot_type']
            pred_shot_type = self._normalize_shot_type(pred.get('range'))
            
            if gt_shot_type and pred_shot_type:
                if gt_shot_type == pred_shot_type:
                    shot_type_correct += 1
                
                # Confusion matrix
                key = f"{gt_shot_type} -> {pred_shot_type}"
                shot_type_confusion[key] = shot_type_confusion.get(key, 0) + 1
            
            # Result accuracy (make/miss)
            gt_result = gt['result']
            pred_result = self._normalize_result(pred.get('make_miss'))
            
            if gt_result and pred_result:
                if gt_result == pred_result:
                    result_correct += 1
                
                # Confusion matrix
                key = f"{gt_result} -> {pred_result}"
                result_confusion[key] = result_confusion.get(key, 0) + 1
            
            # Both correct
            if (gt_shot_type == pred_shot_type and gt_result == pred_result):
                both_correct += 1
            
            # Confidence scores
            if pred.get('confidence') is not None:
                confidence_scores.append(pred['confidence'])
        
        # Calculate final metrics
        metrics = {
            'total_samples': len(results),
            'valid_predictions': valid_predictions,
            'parse_success_rate': valid_predictions / len(results) if results else 0,
            'shot_type_accuracy': shot_type_correct / valid_predictions if valid_predictions else 0,
            'result_accuracy': result_correct / valid_predictions if valid_predictions else 0,
            'both_correct_accuracy': both_correct / valid_predictions if valid_predictions else 0,
            'average_confidence': sum(confidence_scores) / len(confidence_scores) if confidence_scores else 0,
            'shot_type_confusion_matrix': shot_type_confusion,
            'result_confusion_matrix': result_confusion
        }
        
        return metrics
    
    def _normalize_shot_type(self, shot_type: Optional[str]) -> Optional[str]:
        """Normalize shot type to match database format."""
        if not shot_type:
            return None
        
        mapping = {
            "LAY_UP": "lay_up",
            "IN_PAINT": "in_paint", 
            "MID_RANGE": "mid_range",
            "THREE_POINTER": "three_pointer",
            "FREE_THROW": "free_throw"
        }
        
        return mapping.get(shot_type.upper(), shot_type.lower())
    
    def _normalize_result(self, result: Optional[str]) -> Optional[str]:
        """Normalize make/miss result to match database format."""
        if not result:
            return None
        
        result_upper = result.upper()
        if result_upper == "MAKE":
            return "make"
        elif result_upper == "MISS":
            return "miss"
        
        return None
    
    def _save_results(
        self, 
        model_name: str, 
        results: List[Dict], 
        metrics: Dict, 
        prompt: str, 
        fps: int, 
        media_resolution: str
    ) -> None:
        """Save evaluation results to file."""
        # Create model-specific directory
        model_dir = self.output_dir / model_name.replace("/", "_").replace("models_", "")
        model_dir.mkdir(exist_ok=True)
        
        # Generate filename with timestamp
        timestamp = int(time.time())
        filename = f"eval_{timestamp}_fps{fps}_{media_resolution.lower()}.json"
        
        # Save comprehensive results
        output_data = {
            'model_name': model_name,
            'evaluation_timestamp': timestamp,
            'configuration': {
                'fps': fps,
                'media_resolution': media_resolution,
                'prompt': prompt
            },
            'metrics': metrics,
            'results': results
        }
        
        output_path = model_dir / filename
        with open(output_path, 'w') as f:
            json.dump(output_data, f, indent=2, default=str)
        
        print(f"Saved results to {output_path}")
