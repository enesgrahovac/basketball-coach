"""
Data management utilities for the basketball shot analysis evaluation framework.
Handles Supabase integration, video downloads, and ground truth preparation.
"""

import os
import json
import requests
from typing import Dict, List, Optional, Tuple
from pathlib import Path
from supabase import create_client, Client
from tqdm import tqdm
import pandas as pd


class EvaluationDataManager:
    """Manages data synchronization between Supabase and local evaluation dataset."""
    
    def __init__(self, supabase_url: str, supabase_key: str, data_dir: str = "data"):
        """Initialize data manager with Supabase credentials."""
        self.supabase: Client = create_client(supabase_url, supabase_key)
        self.data_dir = Path(data_dir)
        self.videos_dir = self.data_dir / "videos"
        self.ground_truth_file = self.data_dir / "ground_truth.json"
        
        # Ensure directories exist
        self.data_dir.mkdir(exist_ok=True)
        self.videos_dir.mkdir(exist_ok=True)
    
    def fetch_evaluation_dataset(self) -> pd.DataFrame:
        """
        Fetch clips with analysis and user overrides from Supabase.
        Returns a DataFrame with ground truth labels.
        """
        print("Fetching clips and analysis from Supabase...")
        
        # Query for clips with completed analysis
        query = """
        SELECT 
            c.id as clip_id,
            c.storage_key,
            c.duration_s,
            c.created_at as clip_created_at,
            a.id as analysis_id,
            a.shot_type as original_shot_type,
            a.result as original_result,
            a.confidence,
            a.tips_text,
            a.completed_at,
            COALESCE(
                (SELECT override_value FROM analysis_overrides ao1 
                 WHERE ao1.analysis_id = a.id AND ao1.field_name = 'shot_type' 
                 ORDER BY ao1.created_at DESC LIMIT 1),
                a.shot_type
            ) as ground_truth_shot_type,
            COALESCE(
                (SELECT override_value FROM analysis_overrides ao2 
                 WHERE ao2.analysis_id = a.id AND ao2.field_name = 'result' 
                 ORDER BY ao2.created_at DESC LIMIT 1),
                a.result
            ) as ground_truth_result
        FROM clips c
        JOIN analysis a ON c.id = a.clip_id
        WHERE a.status = 'success'
        ORDER BY c.created_at DESC
        """
        
        try:
            response = self.supabase.rpc('execute_sql', {'query': query}).execute()
            data = response.data
        except:
            # Fallback to individual table queries if RPC doesn't work
            print("Using fallback query method...")
            clips_response = self.supabase.table('clips').select('*').execute()
            analysis_response = self.supabase.table('analysis').select('*').eq('status', 'success').execute()
            overrides_response = self.supabase.table('analysis_overrides').select('*').execute()
            
            # Process data manually
            data = self._process_fallback_data(clips_response.data, analysis_response.data, overrides_response.data)
        
        df = pd.DataFrame(data)
        print(f"Found {len(df)} clips with completed analysis")
        
        return df
    
    def _process_fallback_data(self, clips_data: List[Dict], analysis_data: List[Dict], overrides_data: List[Dict]) -> List[Dict]:
        """Process data when RPC query isn't available."""
        # Create lookup dictionaries
        clips_dict = {clip['id']: clip for clip in clips_data}
        analysis_dict = {analysis['clip_id']: analysis for analysis in analysis_data}
        
        # Group overrides by analysis_id and field_name
        overrides_dict = {}
        for override in overrides_data:
            key = (override['analysis_id'], override['field_name'])
            if key not in overrides_dict or override['created_at'] > overrides_dict[key]['created_at']:
                overrides_dict[key] = override
        
        # Combine data
        result = []
        for clip_id, clip in clips_dict.items():
            if clip_id in analysis_dict:
                analysis = analysis_dict[clip_id]
                
                # Get overrides
                shot_type_override = overrides_dict.get((analysis['id'], 'shot_type'))
                result_override = overrides_dict.get((analysis['id'], 'result'))
                
                combined = {
                    'clip_id': clip_id,
                    'storage_key': clip['storage_key'],
                    'duration_s': clip['duration_s'],
                    'clip_created_at': clip['created_at'],
                    'analysis_id': analysis['id'],
                    'original_shot_type': analysis['shot_type'],
                    'original_result': analysis['result'],
                    'confidence': analysis['confidence'],
                    'tips_text': analysis['tips_text'],
                    'completed_at': analysis['completed_at'],
                    'ground_truth_shot_type': shot_type_override['override_value'] if shot_type_override else analysis['shot_type'],
                    'ground_truth_result': result_override['override_value'] if result_override else analysis['result']
                }
                result.append(combined)
        
        return result
    
    def download_missing_videos(self, df: pd.DataFrame, bucket_name: str = "clips") -> List[str]:
        """
        Download videos that aren't already cached locally.
        Returns list of successfully downloaded clip IDs.
        """
        missing_videos = []
        downloaded = []
        
        for _, row in df.iterrows():
            clip_id = row['clip_id']
            video_path = self.videos_dir / f"{clip_id}.mp4"
            
            if not video_path.exists():
                missing_videos.append((clip_id, row['storage_key']))
        
        if not missing_videos:
            print("All videos already downloaded!")
            return []
        
        print(f"Downloading {len(missing_videos)} missing videos...")
        
        for clip_id, storage_key in tqdm(missing_videos, desc="Downloading videos"):
            try:
                # Get signed URL
                response = self.supabase.storage.from_(bucket_name).create_signed_url(storage_key, 3600)
                signed_url = response['signedURL']
                
                # Download video
                video_response = requests.get(signed_url, timeout=60)
                video_response.raise_for_status()
                
                # Save to local file
                video_path = self.videos_dir / f"{clip_id}.mp4"
                with open(video_path, 'wb') as f:
                    f.write(video_response.content)
                
                downloaded.append(clip_id)
                
            except Exception as e:
                print(f"Failed to download {clip_id}: {e}")
        
        print(f"Successfully downloaded {len(downloaded)} videos")
        return downloaded
    
    def save_ground_truth(self, df: pd.DataFrame) -> None:
        """Save ground truth dataset to JSON file."""
        ground_truth = []
        
        for _, row in df.iterrows():
            entry = {
                'clip_id': row['clip_id'],
                'storage_key': row['storage_key'],
                'duration_s': row['duration_s'],
                'video_path': str(self.videos_dir / f"{row['clip_id']}.mp4"),
                'ground_truth': {
                    'shot_type': row['ground_truth_shot_type'],
                    'result': row['ground_truth_result']
                },
                'original_analysis': {
                    'shot_type': row['original_shot_type'],
                    'result': row['original_result'],
                    'confidence': row['confidence'],
                    'tips_text': row['tips_text']
                },
                'metadata': {
                    'analysis_id': row['analysis_id'],
                    'clip_created_at': row['clip_created_at'],
                    'completed_at': row['completed_at']
                }
            }
            ground_truth.append(entry)
        
        with open(self.ground_truth_file, 'w') as f:
            json.dump(ground_truth, f, indent=2, default=str)
        
        print(f"Saved ground truth dataset with {len(ground_truth)} entries to {self.ground_truth_file}")
    
    def load_ground_truth(self) -> List[Dict]:
        """Load ground truth dataset from JSON file."""
        if not self.ground_truth_file.exists():
            raise FileNotFoundError(f"Ground truth file not found: {self.ground_truth_file}")
        
        with open(self.ground_truth_file, 'r') as f:
            return json.load(f)
    
    def get_dataset_stats(self) -> Dict:
        """Get statistics about the current dataset."""
        try:
            ground_truth = self.load_ground_truth()
        except FileNotFoundError:
            return {"error": "No ground truth dataset found. Run data sync first."}
        
        stats = {
            'total_clips': len(ground_truth),
            'shot_type_distribution': {},
            'result_distribution': {},
            'has_user_corrections': 0,
            'average_duration': 0,
            'videos_downloaded': 0
        }
        
        for entry in ground_truth:
            # Shot type distribution
            shot_type = entry['ground_truth']['shot_type']
            stats['shot_type_distribution'][shot_type] = stats['shot_type_distribution'].get(shot_type, 0) + 1
            
            # Result distribution
            result = entry['ground_truth']['result']
            stats['result_distribution'][result] = stats['result_distribution'].get(result, 0) + 1
            
            # Check for user corrections
            if (entry['ground_truth']['shot_type'] != entry['original_analysis']['shot_type'] or
                entry['ground_truth']['result'] != entry['original_analysis']['result']):
                stats['has_user_corrections'] += 1
            
            # Duration
            stats['average_duration'] += entry['duration_s']
            
            # Check if video exists
            if Path(entry['video_path']).exists():
                stats['videos_downloaded'] += 1
        
        stats['average_duration'] /= len(ground_truth)
        stats['correction_rate'] = stats['has_user_corrections'] / len(ground_truth)
        
        return stats
