// Supabase Serverless Edge Function: predict-demand
// Deploy via: supabase functions deploy predict-demand
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const today = new Date().toISOString().split("T")[0];

    // Fetch today's active menu items
    const { data: menuItems, error: menuErr } = await supabase
      .from("menu_items")
      .select("*")
      .eq("is_available_today", true);

    if (menuErr) throw menuErr;

    // Fetch today's student preferences
    const { data: prefs, error: prefErr } = await supabase
      .from("meal_preferences")
      .select("menu_item_id, quantity")
      .eq("meal_date", today);

    if (prefErr) throw prefErr;

    const results = [];

    for (const item of menuItems || []) {
      const currentPrefs = (prefs || [])
        .filter((p) => p.menu_item_id === item.id)
        .reduce((sum, p) => sum + (p.quantity || 1), 0);

      // Weighted Demand Prediction Formula: 0.7 * Current + 0.3 * Historical
      const predictedDemand = Math.round(
        0.7 * currentPrefs + 0.3 * item.historical_avg
      );

      const { data: upserted, error: upsertErr } = await supabase
        .from("daily_records")
        .upsert(
          {
            menu_item_id: item.id,
            record_date: today,
            current_preferences: currentPrefs,
            historical_avg: item.historical_avg,
            predicted_demand: predictedDemand,
          },
          { onConflict: "menu_item_id,record_date" }
        )
        .select()
        .single();

      if (upsertErr) throw upsertErr;
      results.push({ ...upserted, item_name: item.name });
    }

    return new Response(
      JSON.stringify({
        status: "success",
        engine: "Supabase Serverless Edge Function (Deno)",
        formula: "0.7 * Current_Preferences + 0.3 * Historical_Average",
        date: today,
        predictions: results,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }
});
