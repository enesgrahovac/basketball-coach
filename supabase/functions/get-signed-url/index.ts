import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get the storage key from the request
    const { storageKey } = await req.json()
    
    if (!storageKey) {
      return new Response(
        JSON.stringify({ error: 'Storage key is required' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // Create Supabase client with service role key (server-side only)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Clean storage key (remove clips/ prefix if present)
    let cleanStorageKey = storageKey
    // if (cleanStorageKey.startsWith('clips/')) {
    //   cleanStorageKey = cleanStorageKey.substring(6)
    // }

    console.log(`Generating signed URL for: ${cleanStorageKey}`)

    // Generate signed URL (expires in 1 hour)
    const { data, error } = await supabase.storage
      .from('clips')
      .createSignedUrl(cleanStorageKey, 3600)

    if (error) {
      console.error('Error creating signed URL:', error)
      return new Response(
        JSON.stringify({ error: 'Failed to create signed URL', details: error.message }),
        { 
          status: 500, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    console.log(`Generated signed URL: ${data.signedUrl}`)

    return new Response(
      JSON.stringify({ signedUrl: data.signedUrl }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )

  } catch (error) {
    console.error('Error in get-signed-url function:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})
