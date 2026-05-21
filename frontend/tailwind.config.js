/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{html,ts,scss}'],
  theme: {
    extend: {
      colors: {
        juris: {
          primary: '#1a3a5c',
          accent:  '#c4922a',
          bg:      '#f8f6f1'
        }
      }
    }
  },
  plugins: []
}
