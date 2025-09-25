// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    if (req.method !== 'POST' && req.method !== 'PATCH') {
      return new Response(JSON.stringify({ error: 'Method Not Allowed. Expected POST or PATCH.' }), {
        status: 405,
        headers: { 'Content-Type': 'application/json', ...corsHeaders }
      })
    }

    const contentType = req.headers.get("content-type") || "";
    if (!contentType.includes("application/json")) {
      return new Response(JSON.stringify({ error: "Expected application/json" }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const body = await req.json() as any;
    const { analysis_id, field_name, override_value, original_value } = body;

    // Validate required fields
    if (!analysis_id || !field_name || !override_value) {
      return new Response(JSON.stringify({ 
        error: 'analysis_id, field_name, and override_value are required' 
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json', ...corsHeaders }
      })
    }

    // Validate field_name
    const validFields = ['shot_type', 'result'];
    if (!validFields.includes(field_name)) {
      return new Response(JSON.stringify({ 
        error: `field_name must be one of: ${validFields.join(', ')}` 
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json', ...corsHeaders }
      })
    }

    // Validate override_value based on field_name
    if (field_name === 'shot_type') {
      const validShotTypes = ['lay_up', 'in_paint', 'mid_range', 'three_pointer', 'free_throw'];
      if (!validShotTypes.includes(override_value)) {
        return new Response(JSON.stringify({ 
          error: `For shot_type, override_value must be one of: ${validShotTypes.join(', ')}` 
        }), {
          status: 400,
          headers: { 'Content-Type': 'application/json', ...corsHeaders }
        })
      }
    } else if (field_name === 'result') {
      const validResults = ['make', 'miss'];
      if (!validResults.includes(override_value)) {
        return new Response(JSON.stringify({ 
          error: `For result, override_value must be one of: ${validResults.join(', ')}` 
        }), {
          status: 400,
          headers: { 'Content-Type': 'application/json', ...corsHeaders }
        })
      }
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // First verify the analysis exists
    const { data: analysisExists, error: analysisError } = await supabase
      .from('analysis')
      .select('id')
      .eq('id', analysis_id)
      .single()

    if (analysisError || !analysisExists) {
      return new Response(JSON.stringify({ 
        error: 'Analysis not found' 
      }), {
        status: 404,
        headers: { 'Content-Type': 'application/json', ...corsHeaders }
      })
    }

    // Upsert the override (insert or update if exists)
    const overrideData = {
      analysis_id,
      field_name,
      override_value,
      original_value: original_value || null,
    }

    const { data, error } = await supabase
      .from('analysis_overrides')
      .upsert(overrideData, { 
        onConflict: 'analysis_id,field_name' 
      })
      .select()

    if (error) {
      console.error('Database error:', error)
      return new Response(JSON.stringify({ 
        error: 'Failed to save override',
        details: error.message 
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json', ...corsHeaders }
      })
    }

    return new Response(JSON.stringify({ 
      success: true, 
      data: data?.[0] || null 
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json', ...corsHeaders }
    })

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(JSON.stringify({ 
      error: 'Internal Server Error',
      details: error instanceof Error ? error.message : 'Unknown error'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json', ...corsHeaders }
    })
  }
})
